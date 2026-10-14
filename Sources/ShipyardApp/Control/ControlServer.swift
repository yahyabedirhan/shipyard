import Darwin
import Foundation
import ShipyardControl
import ShipyardCore
import ShipyardNotices

@MainActor
final class ControlServer {
    struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: ControlLease.Term?
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    let socket: URL
    private let panel: any PanelControlling
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    private(set) var lease: ControlLease {
        didSet { leaseChanged() }
    }
    let indicator: LeaseIndicator
    private let transitioned: @MainActor (ControlLease.Transition) -> Void
    private let notices: @MainActor (NoticeRequest) async -> NoticeVerdict
    private let notesCheck: @MainActor () async -> NotesCheckAnswer
    private var settling: Task<Void, Never>?
    private var waiters: [UUID: Waiter] = [:]
    private var listener: Listener?

    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var answer: CheckedContinuation<Answer, Never>
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
        notices: @escaping @MainActor (NoticeRequest) async -> NoticeVerdict = { _ in .refused("this app doesn't show notices") },
        notesCheck: @escaping @MainActor () async -> NotesCheckAnswer = { .refused("this app doesn't read notes") },
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
        self.notices = notices
        self.notesCheck = notesCheck
        self.quit = quit
        // `didSet` doesn't run in `init`: a lease a relaunch handed over is
        // shown, and its end looked out for, from the start.
        leaseChanged()
    }

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
        let step = message.request.step
        let began = now()
        if let step { lease.began(step, by: message.holder, at: began) }
        defer { if step != nil { lease.ended(stepBegunAt: began, by: message.holder, at: now()) } }
        switch message.request {
        case .controlTake(let seconds, let purpose):
            return await take(by: message.holder, waiting: seconds, purpose: purpose)
        case .controlRelease:
            apply(lease.release(by: message.holder, at: now()))
            return Answer(reply: .done("released shipyard\n"))
        case .appStatus(let json):
            let status = status()
            return Answer(reply: .done(json ? status.json : status.text))
        case .appOpen:
            return Answer(reply: .done(status().text))
        case .appQuit:
            granted?.activity = nil
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
        case .panelView(let name):
            return await steer { () throws(PanelRefusal) in "showing \(try panel.showView(name))" }
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
        case .notify(let request):
            switch await notices(request) {
            case .shown, .queued: return Answer(reply: .done(""))
            case .refused(let why): return Answer(reply: .refused(why))
            }
        case .notesCheck:
            switch await notesCheck() {
            case .inOrder(let report): return Answer(reply: .done(report))
            case .refused(let report): return Answer(reply: .refused(report.trimmingCharacters(in: .newlines)))
            }
        }
    }

    private func status() -> AppStatus {
        var status = panel.status()
        status.lease = lease.status(at: now())
        return status
    }

    private func take(by holder: Holder, waiting seconds: Int?, purpose: String?) async -> Answer {
        let time = now()
        let decision = lease.take(
            by: holder, at: time, waitingUntil: seconds.map { time.addingTimeInterval(TimeInterval($0)) }, purpose: purpose
        )
        apply(decision.transitions)
        switch decision.answer {
        case .success(let term):
            return held(term)
        case .failure(.queued):
            break
        case .failure(let refusal):
            return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
        }
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

    private func waitRanOut(_ ticket: UUID, deadline: Date) {
        guard let waiter = waiters.removeValue(forKey: ticket) else { return }
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

    private func held(_ term: ControlLease.Term) -> Answer {
        Answer(reply: .done(term.held(timeZone: timeZone) + "\n"), granted: term)
    }

    func undelivered(_ answer: Answer) {
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        apply(lease.release(by: granted.holder, at: now()))
    }

    func stopLease() {
        apply(lease.stop(at: now()))
    }

    func allow(_ key: String) {
        lease.allow(key, at: now())
    }

    func settleLease() {
        apply(lease.settle(at: now()))
    }

    private func apply(_ transitions: [ControlLease.Transition]) {
        for transition in transitions { transitioned(transition) }
    }

    private func leaseChanged() {
        let time = now()
        indicator.update(lease, at: time)
        settling?.cancel()
        settling = nil
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
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    private func steer(_ body: () async throws(PanelRefusal) -> String) async -> Answer {
        do throws(PanelRefusal) {
            return Answer(reply: .done(try await body() + "\n"))
        } catch {
            return Answer(reply: .refused(error.reason))
        }
    }

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

    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        for waiter in waiters.values {
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("shipyard is quitting")))
        }
        waiters = [:]
    }
}

private final class Listener: @unchecked Sendable {
    typealias Respond = @Sendable (Data) async -> ControlServer.Answer
    typealias Undelivered = @MainActor @Sendable (ControlServer.Answer) -> Void

    private let path: String
    private let source: DispatchSourceRead
    private let respond: Respond
    private let undelivered: Undelivered
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "shipyard.control", attributes: .concurrent)
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
        guard UnixSocket.bindSocket(descriptor, to: address) == 0, chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            unlink(path)
            throw .init(description: "couldn't listen on \(path): \(why)")
        }
        return Listener(path: path, descriptor: descriptor, respond: respond, undelivered: undelivered, quit: quit)
    }

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

    private func acceptAll(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.configure(connection, timeout: Self.connectionTimeout)
            Self.queue.async { self.serve(connection) }
        }
    }

    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: ControlRequest.largestMessage), !request.isEmpty else {
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

enum NotesCheckAnswer: Equatable {
    case inOrder(String)
    case refused(String)
}
