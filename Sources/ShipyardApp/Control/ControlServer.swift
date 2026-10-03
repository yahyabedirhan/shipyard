import Darwin
import Foundation
import ShipyardControl
import ShipyardCore

/// App control's server: while the app runs it listens on `control.sock`
/// in the support folder, the user's own (mode 0600), and answers one JSON
/// request per connection with one reply. Each request is read off the main
/// actor, answered on it (`reply(to:)`), and the reply written back before
/// the connection closes. Every refusal is a reply, so the `shipyard`
/// command always has a line to print. A `take`'s reply granting the lease
/// that can't be written (its client gone) gives the lease up at once.
@MainActor
final class ControlServer {
    /// A reply, whether the app quits once it's written, and the lease a
    /// `control take`'s reply grants, released when the reply can't be
    /// written (`undelivered`).
    struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: ControlLease.Term?
    }

    /// Why the server couldn't start listening.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    let socket: URL
    private let panel: any PanelControlling
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
    /// The time the lease is decided at, and the zone its refusals name it in.
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    /// App control's lease: who may send leased requests, and until when.
    /// Each change is shown (`indicator`) and its end looked out for.
    private(set) var lease: ControlLease {
        didSet { leaseChanged() }
    }
    /// The dot and the banner, which follow the lease.
    let indicator: LeaseIndicator
    /// Told each change in who holds the lease, in order: the app posts
    /// the lease's notifications from them. A relaunch's handover isn't one.
    private let transitioned: @MainActor (ControlLease.Transition) -> Void
    /// Ends the lease once it runs out, when no request comes to.
    private var settling: Task<Void, Never>?
    /// The `take`s waiting in line, each holding its connection open until
    /// it gets the lease or its wait runs out.
    private var waiters: [UUID: Waiter] = [:]
    private var listener: Listener?

    /// A `take` waiting in line: who sent it, how long it waits, and how it
    /// gets its answer.
    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var answer: CheckedContinuation<Answer, Never>
        /// Ends the wait when it runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    init(
        socket: URL,
        panel: any PanelControlling,
        screenshotter: any Screenshotting,
        lease: ControlLease = ControlLease(),
        indicator: LeaseIndicator,
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        transitioned: @escaping @MainActor (ControlLease.Transition) -> Void = { _ in },
        quit: @escaping @MainActor () -> Void
    ) {
        self.socket = socket
        self.panel = panel
        self.screenshotter = screenshotter
        self.lease = lease
        self.indicator = indicator
        self.now = now
        self.timeZone = timeZone
        self.transitioned = transitioned
        self.quit = quit
        // `didSet` doesn't run in `init`: a lease a relaunch handed over is
        // shown, and its end looked out for, from the start.
        leaseChanged()
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. A leased request
    /// asks the lease first: refused for anyone but its holder, with
    /// nothing done. A quit hands the lease back in its reply, for a
    /// relaunch to pass on. A `take` that waits in line is answered once it
    /// gets the lease or its wait runs out, other requests answered
    /// meanwhile.
    func reply(to data: Data) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        var granted: ControlLease.Term?
        if message.request.isLeased {
            let time = now()
            let decision = lease.use(by: message.holder, at: time)
            apply(decision.transitions)
            switch decision.answer {
            case .success(let term): granted = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        switch message.request {
        case .controlTake(let seconds):
            return await take(by: message.holder, waiting: seconds)
        case .controlRelease:
            // The next waiter's take is answered as the lease changes (`leaseChanged`).
            apply(lease.release(by: message.holder, at: now()))
            return Answer(reply: .done("released shipyard\n"))
        case .appStatus(let json):
            let status = status()
            return Answer(reply: .done(json ? status.json : status.text))
        case .appOpen:
            return Answer(reply: .done(status().text))
        case .appQuit:
            return Answer(reply: ControlReply(ok: true, output: "shipyard quit\n", lease: granted), quits: true)
        case .panelOpen:
            return await steer { () async throws(PanelRefusal) in try await panel.open(); return "panel open" }
        case .panelClose:
            return await steer { () async throws(PanelRefusal) in try await panel.close(); return "panel closed" }
        case .panelFold(let project):
            return await steer { () throws(PanelRefusal) in try panel.fold(project); return "folded \(project)" }
        case .panelUnfold(let project):
            return await steer { () throws(PanelRefusal) in try panel.unfold(project); return "unfolded \(project)" }
        case .panelShowMore(let project, let kind):
            return await steer { () throws(PanelRefusal) in
                try panel.showMore(project, kind: kind)
                return "showing all \(kind) in \(project)"
            }
        case .panelTab(let name):
            return await steer { () throws(PanelRefusal) in "showing \(try panel.selectTab(name))" }
        case .screenshot(let path, let appearance, let menuBarIcon, let withIndicator):
            let file = URL(fileURLWithPath: path)
            let outcome = menuBarIcon
                ? await screenshotter.menuBarIcon(to: file, appearance: appearance, withIndicator: withIndicator)
                : await screenshotter.capturePanel(to: file, appearance: appearance, withIndicator: withIndicator)
            switch outcome {
            case .captured:
                return Answer(reply: .done(path + "\n"))
            case .rendered(let why):
                return Answer(reply: .done(path + "\n", note: "captured by rendering: \(why)\n"))
            case .failed(let why):
                return Answer(reply: .refused(why))
            }
        }
    }

    /// The panel's status, with the lease as it is now.
    private func status() -> AppStatus {
        var status = panel.status()
        status.lease = lease.status(at: now())
        return status
    }

    // MARK: - Taking turns

    /// `control take`: held to the cap at once when the lease is the
    /// holder's or free. While another holds it, refused at once without a
    /// wait; with one, the take waits in line, suspended so the main actor
    /// answers other requests (the holder's release among them), until
    /// `leaseChanged` finds the lease handed to it or its wait runs out.
    private func take(by holder: Holder, waiting seconds: Int?) async -> Answer {
        let time = now()
        let decision = lease.take(by: holder, at: time, waitingUntil: seconds.map { time.addingTimeInterval(TimeInterval($0)) })
        apply(decision.transitions)
        switch decision.answer {
        case .success(let term):
            return held(term)
        case .failure(.queued):
            break
        case .failure(let refusal):
            return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
        }
        // Queued only with a wait after now.
        let seconds = seconds ?? 0
        let deadline = time.addingTimeInterval(TimeInterval(seconds))
        let ticket = UUID()
        return await withCheckedContinuation { continuation in
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                self?.waitRanOut(ticket, deadline: deadline)
            }
            waiters[ticket] = Waiter(holder: holder, seconds: seconds, answer: continuation, timeout: timeout)
        }
    }

    /// A waiting `take`'s wait ran out (unless it was answered already): it
    /// leaves the line, refused with who still holds the lease, or holding
    /// it should it be free by now.
    private func waitRanOut(_ ticket: UUID, deadline: Date) {
        guard let waiter = waiters.removeValue(forKey: ticket) else { return }
        // Never before the deadline the take was given, whatever the clock says.
        let time = max(now(), deadline)
        let decision = lease.giveUp(by: waiter.holder, waited: waiter.seconds, at: time)
        apply(decision.transitions)
        switch decision.answer {
        case .success(let term):
            waiter.answer.resume(returning: held(term))
        case .failure(let refusal):
            waiter.answer.resume(returning: Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone))))
        }
    }

    /// A `take`'s answer holding the lease to `term`'s end, which it grants.
    private func held(_ term: ControlLease.Term) -> Answer {
        Answer(reply: .done(term.held(timeZone: timeZone) + "\n"), granted: term)
    }

    /// A `take`'s reply that granted the lease couldn't be written: its
    /// client has gone (stopped, or cut off by its harness's timeout while
    /// it waited in line), so nobody knows they hold it. The lease is given
    /// up for that holder at once (`released`), and the next waiter gets it
    /// as usual, rather than it sitting unused until it runs out. A lease
    /// that has moved on meanwhile (another holder's, or a new one) is left
    /// alone.
    func undelivered(_ answer: Answer) {
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        apply(lease.release(by: granted.holder, at: now()))
    }

    // MARK: - The maintainer taking shipyard back

    /// The banner's Stop: the holder's lease ends and it's barred
    /// (`ControlLease.stop`), and the first waiter in line gets the lease,
    /// its `take` answered as the lease changes. The maintainer's only way
    /// into the lease, with `allow`.
    func stopLease() {
        apply(lease.stop(at: now()))
    }

    /// A quiet line's Allow: the bar on the holder with `key` is lifted.
    func allow(_ key: String) {
        lease.allow(key, at: now())
    }

    // MARK: - The lease's end

    /// Ends the lease if it has run out by now, handing it to the first
    /// waiter in line, and lifts the bars that have ended. A timer calls it
    /// at the next of those ends, so the dot, the banner and a quiet line
    /// go, and the waiter gets the lease, with no request.
    func settleLease() {
        apply(lease.settle(at: now()))
    }

    /// Tells `transitioned` each change in who holds the lease, in order,
    /// as the lease reported it: every call that changes the lease hands
    /// its transitions here.
    private func apply(_ transitions: [ControlLease.Transition]) {
        for transition in transitions { transitioned(transition) }
    }

    /// The one place a change to the lease is applied: it's shown as it is
    /// now, a holder that got it from the line has its waiting `take`s
    /// answered, and its next end (the lease's or a bar's) is looked out
    /// for, the timer set for the last change replaced by one for this one.
    private func leaseChanged() {
        if indicator.lease != lease { indicator.lease = lease }
        settling?.cancel()
        settling = nil
        let time = now()
        if let term = lease.current(at: time) {
            for (ticket, waiter) in waiters where waiter.holder.key == term.holder.key {
                waiters[ticket] = nil
                waiter.timeout?.cancel()
                waiter.answer.resume(returning: held(term))
            }
        }
        guard let next = lease.nextEnd(after: time) else { return }
        let left = next.timeIntervalSince(time)
        settling = Task { [weak self] in
            // A wake before the end settles nothing, and sets the timer again.
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    /// The line `body` returns, done, or its refusal.
    private func steer(_ body: () async throws(PanelRefusal) -> String) async -> Answer {
        do throws(PanelRefusal) {
            return Answer(reply: .done(try await body() + "\n"))
        } catch {
            return Answer(reply: .refused(error.reason))
        }
    }

    // MARK: - Listening

    /// Starts listening, creating the support folder when it's missing. A
    /// socket file nothing answers on (left by an app that crashed) is
    /// replaced; one another app answers on is left alone, and this one
    /// doesn't listen.
    func start() throws(Failure) {
        guard listener == nil else { return }
        let listener = try Listener.open(at: socket) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("shipyard is quitting"))
        } undelivered: { [weak self] answer in
            self?.undelivered(answer)
        } quit: { [weak self] in
            self?.quit()
        }
        self.listener = listener
    }

    /// Stops listening and removes the socket, so the `shipyard` command
    /// finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        // A take waiting in line hears why, rather than a dropped connection.
        for waiter in waiters.values {
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("shipyard is quitting")))
        }
        waiters = [:]
    }
}

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the
/// server answer it, writes the reply and closes. A reply granting the
/// lease that can't be written goes back to the server (`undelivered`).
private final class Listener: @unchecked Sendable {
    typealias Respond = @Sendable (Data) async -> ControlServer.Answer
    typealias Undelivered = @MainActor @Sendable (ControlServer.Answer) -> Void

    private let path: String
    private let source: DispatchSourceRead
    private let respond: Respond
    private let undelivered: Undelivered
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "shipyard.control", attributes: .concurrent)
    /// How long a connection may take to send its request or read the
    /// reply, so a client that stalls never holds a thread.
    private static let connectionTimeout: TimeInterval = 5

    private init(
        path: String, descriptor: Int32, respond: @escaping Respond, undelivered: @escaping Undelivered,
        quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.path = path
        self.respond = respond
        self.undelivered = undelivered
        self.quit = quit
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    static func open(
        at socket: URL,
        respond: @escaping Respond,
        undelivered: @escaping Undelivered,
        quit: @escaping @MainActor @Sendable () -> Void
    ) throws(ControlServer.Failure) -> Listener {
        let path = socket.path
        guard let address = UnixSocket.address(path) else { throw .init(description: UnixSocket.tooLong(path)) }
        do {
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .init(description: "couldn't create \(socket.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        if FileManager.default.fileExists(atPath: path) {
            guard !answers(address) else { throw .init(description: "another shipyard already listens on \(path)") }
            unlink(path)
        }
        let descriptor = UnixSocket.make()
        guard descriptor >= 0 else { throw .init(description: "couldn't open a socket: \(UnixSocket.reason())") }
        // Owner-only before anyone can connect: connections wait for listen(2).
        guard UnixSocket.bindSocket(descriptor, to: address) == 0, chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            unlink(path)
            throw .init(description: "couldn't listen on \(path): \(why)")
        }
        return Listener(path: path, descriptor: descriptor, respond: respond, undelivered: undelivered, quit: quit)
    }

    /// Whether something accepts a connection at `address`.
    private static func answers(_ address: sockaddr_un) -> Bool {
        let probe = UnixSocket.make()
        guard probe >= 0 else { return false }
        defer { Darwin.close(probe) }
        return UnixSocket.connectSocket(probe, to: address) == 0
    }

    func close() {
        source.cancel()
        unlink(path)
    }

    /// Accepts every waiting connection; the listening socket doesn't block.
    private func acceptAll(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            // An accepted socket inherits O_NONBLOCK; its reads wait, up to the timeout.
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.configure(connection, timeout: Self.connectionTimeout)
            Self.queue.async { self.serve(connection) }
        }
    }

    /// Answers one connection. One that sends nothing, such as another
    /// app's look at whether this one listens, gets no reply. The client
    /// half-closes once it has sent, so its hanging up shows only when the
    /// reply can't be written (`EPIPE`): a granted lease then goes back.
    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let undelivered = undelivered
        let quit = quit
        Task {
            let answer = await respond(request)
            let delivered = UnixSocket.writeAll(connection, answer.reply.encoded())
            Darwin.close(connection)
            if !delivered, answer.granted != nil { await undelivered(answer) }
            if answer.quits { await quit() }
        }
    }
}
