import Darwin
import Foundation
@testable import ShipyardApp
import ShipyardControl
import ShipyardCore
import Testing

/// App control's server: how it answers each request (with a fake panel),
/// and the real socket, from the `shipyard` command's client to the server
/// and back, in a temporary folder.
@Suite("The control server")
@MainActor
struct ControlServerTests {
    static let status = AppStatus(version: "0.2.0", panelOpen: true, layout: "list", projects: ["shop"])

    /// Records each call it's asked to make, and refuses all of them with
    /// `refusal` when it's set.
    final class FakePanel: PanelControlling {
        var calls: [String] = []
        var refusal: PanelRefusal?

        func status() -> AppStatus { ControlServerTests.status }

        private func record(_ call: String) throws(PanelRefusal) {
            calls.append(call)
            if let refusal { throw refusal }
        }

        func open() async throws(PanelRefusal) { try record("open") }
        func close() async throws(PanelRefusal) { try record("close") }
        func fold(_ project: String) throws(PanelRefusal) { try record("fold \(project)") }
        func unfold(_ project: String) throws(PanelRefusal) { try record("unfold \(project)") }
        func showMore(_ project: String, kind: String) throws(PanelRefusal) { try record("show-more \(project) \(kind)") }
        func selectTab(_ name: String) throws(PanelRefusal) -> String {
            try record("tab \(name)")
            return name == "all" ? "All" : name
        }
    }

    /// Records each screenshot it's asked for, and answers with `outcome`.
    final class FakeScreenshotter: Screenshotting {
        var calls: [String] = []
        var outcome = ScreenshotOutcome.captured

        func capturePanel(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome {
            calls.append("panel \(file.path) \(appearance?.rawValue ?? "as is")\(withIndicator ? " with indicator" : "")")
            return outcome
        }

        func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome {
            calls.append("icon \(file.path) \(appearance?.rawValue ?? "as is")\(withIndicator ? " with indicator" : "")")
            return outcome
        }
    }

    /// Whether the server asked the app to quit.
    final class QuitRecorder {
        var quits = 0
    }

    /// The lease's notices, as the app makes them from the transitions the
    /// server tells: what it would hand the notifier, in order.
    final class NoticeRecorder {
        var notices: [ControlNotice] = []
    }

    /// The time the server decides the lease at, moved by the test.
    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    /// The agent the tests' requests come from, and another one.
    nonisolated static let agent = Holder(key: "CLAUDE_CODE_SESSION_ID=agent", name: "Claude Code", place: "/work")
    nonisolated static let other = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
    /// `agent` as it reads in a request on the wire.
    nonisolated static let agentWire = #""holder":{"key":"CLAUDE_CODE_SESSION_ID=agent","name":"Claude Code","place":"\/work"}"#

    let panel = FakePanel()
    let screenshotter = FakeScreenshotter()
    let quitter = QuitRecorder()
    let clock = Clock()
    let indicator = LeaseIndicator()
    /// A folder of its own for each test, short enough for a socket's path.
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("shipyard-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { ControlSocket.url(in: folder) }

    /// A `shipyard` command's exchange, as it runs in its own process: on a
    /// thread of its own, since `send` blocks until the app answers. On
    /// Swift's cooperative pool (`Task.detached`) each blocked send holds one
    /// of its few threads, and with the suites running in parallel, and a
    /// `take` waiting in line for seconds, they left none for the server's
    /// own tasks to answer with: every exchange timed out.
    nonisolated static func sending(
        _ send: @escaping @Sendable () -> Result<ControlReply, ControlClient.Failure>
    ) async -> Result<ControlReply, ControlClient.Failure> {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: send()) }
        }
    }

    let recorder = NoticeRecorder()

    func server(
        socket: URL = URL(fileURLWithPath: "/nonexistent/control.sock"),
        lease: ControlLease = ControlLease()
    ) -> ControlServer {
        let quitter = quitter
        let clock = clock
        let recorder = recorder
        return ControlServer(
            socket: socket,
            panel: panel,
            screenshotter: screenshotter,
            lease: lease,
            indicator: indicator,
            now: { clock.now },
            timeZone: TimeZone(identifier: "UTC")!,
            transitioned: { transition in
                if let notice = ControlNotice(transition) { recorder.notices.append(notice) }
            },
            quit: { quitter.quits += 1 }
        )
    }

    // MARK: - Dispatch

    @Test("status answers with the panel's status, as lines or as JSON")
    func status() async {
        let server = server()

        let text = await server.reply(to: ControlRequest.appStatus(json: false).sent())
        let json = await server.reply(to: ControlRequest.appStatus(json: true).sent())

        #expect(text == .init(reply: .done(Self.status.text)))
        #expect(json == .init(reply: .done(Self.status.json)))
    }

    @Test("quit answers with the lease it renewed, for a relaunch to hand over, and quits once the reply is written")
    func quit() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 20)

        let answer = await server.reply(to: ControlRequest.appQuit.sent())

        let lease = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 80))
        #expect(answer == .init(reply: ControlReply(ok: true, output: "shipyard quit\n", lease: lease), quits: true))
        #expect(quitter.quits == 0)
    }

    @Test("open, against the running app, is leased: it renews the lease and answers with the status as lines")
    func open() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 30)

        let answer = await server.reply(to: ControlRequest.appOpen.sent())

        var held = Self.status
        held.lease = AppStatus.Lease(holder: "Claude Code", place: "/work", secondsLeft: 60, waiting: 0)
        #expect(answer == .init(reply: .done(held.text)))
        #expect(server.lease.current(at: clock.now)?.ends == Date(timeIntervalSince1970: 90))
    }

    @Test("each panel request asks the panel once and answers with what it did", arguments: [
        (ControlRequest.panelOpen, "open", "panel open\n"),
        (.panelClose, "close", "panel closed\n"),
        (.panelFold(project: "shop"), "fold shop", "folded shop\n"),
        (.panelUnfold(project: "shop"), "unfold shop", "unfolded shop\n"),
        (.panelShowMore(project: "shop", kind: "issues"), "show-more shop issues", "showing all issues in shop\n"),
        (.panelTab(name: "all"), "tab all", "showing All\n"),
    ])
    func panel(request: ControlRequest, call: String, output: String) async {
        let answer = await server().reply(to: request.sent())

        #expect(answer == .init(reply: .done(output)))
        #expect(panel.calls == [call])
    }

    @Test("a panel request the panel refuses is answered with its reason", arguments: [
        ControlRequest.panelOpen, .panelFold(project: "shopp"), .panelShowMore(project: "shop", kind: "prs"), .panelTab(name: "x"),
    ])
    func panelRefused(request: ControlRequest) async {
        panel.refusal = PanelRefusal("what exists is named here")

        let answer = await server().reply(to: request.sent())

        #expect(answer == .init(reply: .refused("what exists is named here")))
        #expect(panel.calls.count == 1)
    }

    @Test("a screenshot asks the screenshotter once: captured prints the path, rendered adds why on standard error, failed refuses", arguments: [
        (ScreenshotOutcome.captured, ControlReply.done("/tmp/shop.png\n")),
        (.rendered(why: "ScreenCaptureKit: declined"), .done("/tmp/shop.png\n", note: "captured by rendering: ScreenCaptureKit: declined\n")),
        (.failed(why: "couldn't write /tmp/shop.png"), .refused("couldn't write /tmp/shop.png")),
    ])
    func screenshot(outcome: ScreenshotOutcome, reply: ControlReply) async {
        screenshotter.outcome = outcome
        let server = server()

        let shot = await server.reply(to: ControlRequest.screenshot(
            path: "/tmp/shop.png", appearance: .dark, menuBarIcon: false, withIndicator: false
        ).sent())
        let icon = await server.reply(to: ControlRequest.screenshot(
            path: "/tmp/shop.png", appearance: nil, menuBarIcon: true, withIndicator: true
        ).sent())

        #expect(shot == .init(reply: reply))
        #expect(icon == .init(reply: reply))
        #expect(screenshotter.calls == ["panel /tmp/shop.png dark", "icon /tmp/shop.png as is with indicator"])
        #expect(panel.calls.isEmpty)
    }

    @Test("a screenshot without an absolute path, or with an unknown appearance, is refused and nothing is captured", arguments: [
        (#"{"version":2,"command":"screenshot",\#(ControlServerTests.agentWire),"path":"shop.png"}"#,
         "the control command `screenshot` needs an absolute `path`, not `shop.png`"),
        (#"{"version":2,"command":"screenshot",\#(ControlServerTests.agentWire),"path":"/tmp/shop.png","appearance":"sepia"}"#,
         "the control command `screenshot` has no appearance `sepia`; it takes `light` or `dark`"),
        (#"{"version":2,"command":"screenshot",\#(ControlServerTests.agentWire)}"#, "the control command `screenshot` needs its `path`"),
    ])
    func screenshotUnreadable(request: String, why: String) async {
        let answer = await server().reply(to: Data(request.utf8))

        #expect(answer == .init(reply: .refused(why)))
        #expect(screenshotter.calls.isEmpty)
    }

    @Test("a panel request without the field it needs is refused, and the panel isn't asked")
    func panelMissingField() async {
        let answer = await server().reply(to: Data(#"{"version":2,"command":"panel.showMore",\#(ControlServerTests.agentWire),"project":"shop"}"#.utf8))

        #expect(answer == .init(reply: .refused("the control command `panel.showMore` needs its `kind`")))
        #expect(panel.calls.isEmpty)
    }

    @Test("a request of another version, without a holder, of an unknown command, with a negative wait or not JSON is refused with a reply that says so", arguments: [
        (#"{"version":1,"command":"panel.open"}"#,
         "the shipyard command speaks control version 1 and the app version 2: reinstall shipyard so both come from one build"),
        (#"{"version":2,"command":"panel.open"}"#, "the control command `panel.open` needs its `holder`"),
        (#"{"version":2,"command":"app.spin",\#(ControlServerTests.agentWire)}"#, "the app doesn't know the control command `app.spin`"),
        (#"{"version":2,"command":"control.take",\#(ControlServerTests.agentWire),"waitSeconds":-1}"#,
         "the control command `control.take` needs a `waitSeconds` of 0 or more, not -1"),
        ("status please", "the request isn't a control request"),
    ])
    func refused(request: String, why: String) async {
        let server = server()

        let answer = await server.reply(to: Data(request.utf8))

        #expect(answer == .init(reply: .refused(why)))
        #expect(panel.calls.isEmpty)
        // Nothing that didn't read takes the lease.
        #expect(server.lease.current(at: clock.now) == nil)
    }

    // MARK: - The lease

    @Test("a leased request from another holder is refused, naming the holder, with nothing done", arguments: [
        ControlRequest.appQuit, .appOpen, .panelOpen, .panelClose, .panelFold(project: "shop"), .panelUnfold(project: "shop"),
        .panelShowMore(project: "shop", kind: "issues"), .panelTab(name: "All"),
        .screenshot(path: "/tmp/shop.png", appearance: nil, menuBarIcon: false, withIndicator: false),
        .screenshot(path: "/tmp/shop.png", appearance: .dark, menuBarIcon: true, withIndicator: true),
    ])
    func refusedToAnother(request: ControlRequest) async {
        let server = server()
        // The agent's first leased request takes the lease, for a minute.
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 12)

        let answer = await server.reply(to: request.sent(by: Self.other))

        #expect(answer == .init(reply: .refused(
            "shipyard is in use by Claude Code in /work until 00:01:00 (48s left); `shipyard control take --wait <seconds>` to queue"
        )))
        #expect(panel.calls == ["open"])
        #expect(screenshotter.calls.isEmpty)
        #expect(quitter.quits == 0)
    }

    @Test("the holder's requests renew the lease; once it runs out, another holder takes it")
    func holderThenAnother() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 50)
        let renewed = await server.reply(to: ControlRequest.panelFold(project: "shop").sent())
        clock.now = Date(timeIntervalSince1970: 109)
        let refused = await server.reply(to: ControlRequest.panelClose.sent(by: Self.other))
        clock.now = Date(timeIntervalSince1970: 110)
        let taken = await server.reply(to: ControlRequest.panelClose.sent(by: Self.other))

        #expect(renewed == .init(reply: .done("folded shop\n")))
        #expect(refused.reply.ok == false)
        #expect(taken == .init(reply: .done("panel closed\n")))
        #expect(panel.calls == ["open", "fold shop", "close"])
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)
    }

    @Test("the dot and the banner follow the lease: shown from the request that takes it, gone once it's settled at its end, with no request")
    func indicatorFollowsTheLease() async {
        let server = server()
        #expect(indicator.shown(at: clock.now) == nil)

        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 12)
        // Another agent's refused request changes nothing shown.
        _ = await server.reply(to: ControlRequest.panelClose.sent(by: Self.other))

        #expect(indicator.shown(at: clock.now) == AppStatus.Lease(holder: "Claude Code", place: "/work", secondsLeft: 48, waiting: 0))
        #expect(indicator.shownEnd(at: clock.now) == Date(timeIntervalSince1970: 60))
        // Its end comes with no request: the server's timer settles it.
        clock.now = Date(timeIntervalSince1970: 60)
        server.settleLease()
        #expect(indicator.lease == ControlLease())
        #expect(indicator.shown(at: clock.now) == nil)
        // A capture without the indicator hides a lease that's held.
        _ = await server.reply(to: ControlRequest.panelOpen.sent(by: Self.other))
        indicator.hideForCapture()
        #expect(indicator.shown(at: clock.now) == nil)
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)
    }

    @Test("each lease makes one start and one end notice: renewals and refusals make none, and an end comes by the timer or by the next request")
    func noticesPerLease() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 30)
        _ = await server.reply(to: ControlRequest.panelFold(project: "shop").sent())
        clock.now = Date(timeIntervalSince1970: 40)
        _ = await server.reply(to: ControlRequest.panelClose.sent(by: Self.other))
        _ = await server.reply(to: ControlRequest.appStatus(json: false).sent(by: Self.other))
        // The renewal at 30 moved its end to 90, where the timer settles it.
        clock.now = Date(timeIntervalSince1970: 90)
        server.settleLease()
        clock.now = Date(timeIntervalSince1970: 100)
        _ = await server.reply(to: ControlRequest.panelClose.sent(by: Self.other))
        // Ended with no timer: the next request settles it before it takes the lease.
        clock.now = Date(timeIntervalSince1970: 170)
        _ = await server.reply(to: ControlRequest.panelOpen.sent())

        #expect(recorder.notices == [
            .started(agent: "Claude Code", place: "/work"),
            .ended(agent: "Claude Code", reason: .ranOut),
            .started(agent: "codex", place: "Herdr pane w1-2"),
            .ended(agent: "codex", reason: .ranOut),
            .started(agent: "Claude Code", place: "/work"),
        ])
    }

    @Test("take, a second take and a waiter's place in line make one start; release makes the end, and the waiter's start")
    func noticesOnTakeAndRelease() async throws {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent())
        clock.now = Date(timeIntervalSince1970: 10)
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent())
        let waiting = Task { await server.reply(to: ControlRequest.controlTake(waitSeconds: 120).sent(by: Self.other)) }
        for _ in 0..<200 where server.lease.waiting(at: clock.now) != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let beforeRelease = recorder.notices

        _ = await server.reply(to: ControlRequest.controlRelease.sent())
        _ = await waiting.value

        #expect(beforeRelease == [.started(agent: "Claude Code", place: "/work")])
        #expect(recorder.notices == [
            .started(agent: "Claude Code", place: "/work"),
            .ended(agent: "Claude Code", reason: .released),
            .started(agent: "codex", place: "Herdr pane w1-2"),
        ])
    }

    @Test("a lease a relaunch handed over makes no start notice; its end, at the original cap, makes one")
    func handedOverLeaseNotices() async {
        clock.now = Date(timeIntervalSince1970: 1000)
        let term = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 750), ends: Date(timeIntervalSince1970: 1030))
        let server = server(lease: ControlLease(environment: ControlLease.handover(term), at: clock.now))
        #expect(recorder.notices.isEmpty)

        clock.now = Date(timeIntervalSince1970: 1010)
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        #expect(recorder.notices.isEmpty)
        // Renewed to 1070, but capped at 750 + 5 minutes.
        clock.now = Date(timeIntervalSince1970: 1050)
        server.settleLease()

        #expect(recorder.notices == [.ended(agent: "Claude Code", reason: .ranOut)])
    }

    @Test("status is never refused, takes no lease, and reports the lease as lines and as JSON")
    func statusReportsTheLease() async {
        let server = server()
        let free = await server.reply(to: ControlRequest.appStatus(json: false).sent(by: Self.other))
        #expect(free == .init(reply: .done(Self.status.text)))
        #expect(server.lease.current(at: clock.now) == nil)

        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        clock.now = Date(timeIntervalSince1970: 12)
        let text = await server.reply(to: ControlRequest.appStatus(json: false).sent(by: Self.other))
        let json = await server.reply(to: ControlRequest.appStatus(json: true).sent(by: Self.other))

        var held = Self.status
        held.lease = AppStatus.Lease(holder: "Claude Code", place: "/work", secondsLeft: 48, waiting: 0)
        #expect(text == .init(reply: .done(held.text)))
        #expect(json == .init(reply: .done(held.json)))
        #expect(text.reply.output.contains("lease: Claude Code in /work, 48s left, 0 waiting\n"))
    }

    @Test("take holds the lease to the cap and says until when; release frees it, and from anyone else changes nothing")
    func takeAndRelease() async {
        let server = server()

        let taken = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent())
        clock.now = Date(timeIntervalSince1970: 10)
        let refused = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other))
        let notTheirs = await server.reply(to: ControlRequest.controlRelease.sent(by: Self.other))
        let stillHeld = server.lease.current(at: clock.now)?.holder
        let released = await server.reply(to: ControlRequest.controlRelease.sent())

        #expect(taken == .init(reply: .done("you hold shipyard until 00:05:00\n")))
        #expect(refused == .init(reply: .refused(
            "shipyard is in use by Claude Code in /work until 00:05:00 (290s left); `shipyard control take --wait <seconds>` to queue"
        )))
        #expect(notTheirs == .init(reply: .done("released shipyard\n")))
        #expect(stillHeld == Self.agent)
        #expect(released == .init(reply: .done("released shipyard\n")))
        #expect(server.lease.current(at: clock.now) == nil)
        #expect(panel.calls.isEmpty)
    }

    @Test("a take whose wait runs out is refused with who still holds the lease, and leaves the line")
    func waitRunsOut() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())

        let waited = await server.reply(to: ControlRequest.controlTake(waitSeconds: 1).sent(by: Self.other))

        #expect(waited == .init(reply: .refused("waited 1s; shipyard is still in use by Claude Code in /work until 00:01:00 (59s left)")))
        #expect(server.lease.status(at: clock.now)?.waiting == 0)
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
    }

    @Test("when the lease runs out with no request, the first waiting take gets it; the dot and the banner show the line, then the waiter")
    func waiterGetsTheLeaseAtItsEnd() async throws {
        let server = server()
        _ = await server.reply(to: ControlRequest.panelOpen.sent())
        let waiting = Task { await server.reply(to: ControlRequest.controlTake(waitSeconds: 120).sent(by: Self.other)) }
        for _ in 0..<200 where server.lease.waiting(at: clock.now) != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let line = indicator.shown(at: clock.now)

        // Its end comes with no request: the server's timer settles it.
        clock.now = Date(timeIntervalSince1970: 60)
        server.settleLease()
        let granted = await waiting.value

        #expect(line?.waiting == 1)
        #expect(granted == .init(reply: .done("you hold shipyard until 00:06:00\n")))
        #expect(indicator.shown(at: clock.now) == AppStatus.Lease(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 300, waiting: 0))
    }

    // MARK: - Stop and Allow

    @Test("after Stop, the stopped agent's leased requests and take are refused with the stop's words and nothing done, until allowed back")
    func stopped() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent())
        clock.now = Date(timeIntervalSince1970: 10)
        server.stopLease()
        clock.now = Date(timeIntervalSince1970: 20)

        var answers: [ControlServer.Answer] = []
        for request in [
            ControlRequest.panelOpen, .panelTab(name: "All"), .appQuit,
            .screenshot(path: "/tmp/shop.png", appearance: nil, menuBarIcon: false, withIndicator: false),
            .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30),
        ] {
            answers.append(await server.reply(to: request.sent()))
        }
        let quietLines = indicator.stopped(at: clock.now).map(\.holder)
        server.allow(Self.agent.key)
        let back = await server.reply(to: ControlRequest.panelOpen.sent())

        #expect(answers == Array(repeating: ControlServer.Answer(reply: .refused("the user took shipyard back; ask them before using it again")), count: 6))
        #expect(quietLines == [Self.agent])
        #expect(back == .init(reply: .done("panel open\n")))
        #expect(panel.calls == ["open"])
        #expect(screenshotter.calls.isEmpty)
        #expect(quitter.quits == 0)
        #expect(indicator.stopped(at: clock.now).isEmpty)
        #expect(recorder.notices == [
            .started(agent: "Claude Code", place: "/work"),
            .ended(agent: "Claude Code", reason: .stopped),
            .started(agent: "Claude Code", place: "/work"),
        ])
    }

    @Test("Stop hands the lease to the first waiting take, answered at once; the banner shows it over the stopped agent's quiet line until the bar ends")
    func stopHandsOver() async throws {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent())
        let waiting = Task { await server.reply(to: ControlRequest.controlTake(waitSeconds: 120).sent(by: Self.other)) }
        for _ in 0..<200 where server.lease.waiting(at: clock.now) != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        clock.now = Date(timeIntervalSince1970: 10)
        server.stopLease()
        let granted = await waiting.value

        #expect(granted == .init(reply: .done("you hold shipyard until 00:05:10\n")))
        #expect(indicator.shown(at: clock.now)?.holder == "codex")
        #expect(indicator.stopped(at: clock.now).map(\.holder) == [Self.agent])
        #expect(recorder.notices == [
            .started(agent: "Claude Code", place: "/work"),
            .ended(agent: "Claude Code", reason: .stopped),
            .started(agent: "codex", place: "Herdr pane w1-2"),
        ])
        // The bar and the waiter's cap end together, with no request: the timer settles both.
        clock.now = Date(timeIntervalSince1970: 310)
        server.settleLease()
        #expect(indicator.lease == ControlLease())
    }

    // MARK: - The socket

    @Test("over the socket, a take waiting in line keeps its connection while others are answered, and gets the lease on release")
    func waitingTake() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server(socket: socket)
        try server.start()
        defer { server.stop() }
        let holder = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let waiter = ControlClient(socket: socket, holder: Self.other, transport: UnixSocketTransport())

        let taken = await Self.sending { holder.send(.controlTake(waitSeconds: nil)) }
        #expect(taken == .success(.done("you hold shipyard until 00:05:00\n")))
        // The waiting client blocks its own thread (`sending`) until the lease is handed over.
        let waiting = Task { await Self.sending { waiter.send(.controlTake(waitSeconds: 30)) } }
        for _ in 0..<200 where server.lease.status(at: clock.now)?.waiting != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let status = await Self.sending { holder.send(.appStatus(json: false)) }
        clock.now = Date(timeIntervalSince1970: 12)
        let released = await Self.sending { holder.send(.controlRelease) }
        let granted = await waiting.value

        guard case .success(let reply) = status else { Issue.record("no status: \(status)"); return }
        #expect(reply.output.contains("lease: Claude Code in /work, 300s left, 1 waiting\n"))
        #expect(released == .success(.done("released shipyard\n")))
        #expect(granted == .success(.done("you hold shipyard until 00:05:12\n")))
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)
    }

    @Test("the socket replaces a leftover file, is the user's own, answers the client, and is gone after stop")
    func socket() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Left by an app that crashed.
        try Data().write(to: socket)
        let server = server(socket: socket)
        let client = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let another = ControlClient(socket: socket, holder: Self.other, transport: UnixSocketTransport())

        try server.start()
        var info = stat()
        #expect(stat(socket.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)

        // The client blocks while it waits, so it runs on a thread of its own (`sending`).
        let status = await Self.sending { client.send(.appStatus(json: true)) }
        #expect(status == .success(.done(Self.status.json)))
        let opened = await Self.sending { client.send(.panelOpen) }
        #expect(opened == .success(.done("panel open\n")))
        // Another agent's quit is refused over the socket, and the app stays.
        let refused = await Self.sending { another.send(.appQuit) }
        #expect(refused == .success(.refused(
            "shipyard is in use by Claude Code in /work until 00:01:00 (60s left); `shipyard control take --wait <seconds>` to queue"
        )))
        let quit = await Self.sending { client.send(.appQuit) }
        let lease = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60))
        #expect(quit == .success(ControlReply(ok: true, output: "shipyard quit\n", lease: lease)))
        for _ in 0..<200 where quitter.quits == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(quitter.quits == 1)

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: socket.path))
        let after = await Self.sending { client.send(.appStatus(json: false)) }
        #expect(after == .failure(.notRunning))
    }

    @Test("a client that leaves before the reply doesn't end the app; the next one is answered")
    func clientLeaves() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server(socket: socket)
        try server.start()
        defer { server.stop() }

        // Sends a request and closes at once: the reply is written to a closed peer.
        let impatient = UnixSocket.make()
        try #require(UnixSocket.connectSocket(impatient, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(impatient, ControlRequest.appStatus(json: false).sent())
        close(impatient)
        try await Task.sleep(nanoseconds: 50_000_000)

        let client = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let status = await Self.sending { client.send(.appStatus(json: false)) }
        #expect(status == .success(.done(Self.status.text)))
    }

    @Test("a second server leaves a socket another one answers on alone")
    func inUse() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = server(socket: socket)
        try first.start()
        defer { first.stop() }

        #expect(throws: ControlServer.Failure.self) { try server(socket: socket).start() }
        #expect(FileManager.default.fileExists(atPath: socket.path))
    }
}

extension ControlRequest {
    /// The request as `holder`'s `shipyard` command sends it.
    fileprivate func sent(by holder: Holder = ControlServerTests.agent) -> Data {
        ControlMessage(self, holder: holder).encoded()
    }
}
