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
    static let status = AppStatus(version: "0.1.0", panelOpen: true, layout: "list", projects: ["shop"])

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

        func capturePanel(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome {
            calls.append("panel \(file.path) \(appearance?.rawValue ?? "as is")")
            return outcome
        }

        func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome {
            calls.append("icon \(file.path) \(appearance?.rawValue ?? "as is")")
            return outcome
        }
    }

    /// Whether the server asked the app to quit.
    final class QuitRecorder {
        var quits = 0
    }

    let panel = FakePanel()
    let screenshotter = FakeScreenshotter()
    let quitter = QuitRecorder()
    /// A folder of its own for each test, short enough for a socket's path.
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("shipyard-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { ControlSocket.url(in: folder) }

    func server(socket: URL = URL(fileURLWithPath: "/nonexistent/control.sock")) -> ControlServer {
        let quitter = quitter
        return ControlServer(socket: socket, panel: panel, screenshotter: screenshotter, quit: { quitter.quits += 1 })
    }

    // MARK: - Dispatch

    @Test("status answers with the panel's status, as lines or as JSON")
    func status() async {
        let server = server()

        let text = await server.reply(to: ControlRequest.appStatus(json: false).encoded())
        let json = await server.reply(to: ControlRequest.appStatus(json: true).encoded())

        #expect(text == .init(reply: .done(Self.status.text)))
        #expect(json == .init(reply: .done(Self.status.json)))
    }

    @Test("quit answers, and quits once the reply is written")
    func quit() async {
        let answer = await server().reply(to: ControlRequest.appQuit.encoded())

        #expect(answer == .init(reply: .done("shipyard quit\n"), quits: true))
        #expect(quitter.quits == 0)
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
        let answer = await server().reply(to: request.encoded())

        #expect(answer == .init(reply: .done(output)))
        #expect(panel.calls == [call])
    }

    @Test("a panel request the panel refuses is answered with its reason", arguments: [
        ControlRequest.panelOpen, .panelFold(project: "shopp"), .panelShowMore(project: "shop", kind: "prs"), .panelTab(name: "x"),
    ])
    func panelRefused(request: ControlRequest) async {
        panel.refusal = PanelRefusal("what exists is named here")

        let answer = await server().reply(to: request.encoded())

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

        let shot = await server.reply(to: ControlRequest.screenshot(path: "/tmp/shop.png", appearance: .dark, menuBarIcon: false).encoded())
        let icon = await server.reply(to: ControlRequest.screenshot(path: "/tmp/shop.png", appearance: nil, menuBarIcon: true).encoded())

        #expect(shot == .init(reply: reply))
        #expect(icon == .init(reply: reply))
        #expect(screenshotter.calls == ["panel /tmp/shop.png dark", "icon /tmp/shop.png as is"])
        #expect(panel.calls.isEmpty)
    }

    @Test("a screenshot without an absolute path, or with an unknown appearance, is refused and nothing is captured", arguments: [
        (#"{"version":1,"command":"screenshot","path":"shop.png"}"#,
         "the control command `screenshot` needs an absolute `path`, not `shop.png`"),
        (#"{"version":1,"command":"screenshot","path":"/tmp/shop.png","appearance":"sepia"}"#,
         "the control command `screenshot` has no appearance `sepia`; it takes `light` or `dark`"),
        (#"{"version":1,"command":"screenshot"}"#, "the control command `screenshot` needs its `path`"),
    ])
    func screenshotUnreadable(request: String, why: String) async {
        let answer = await server().reply(to: Data(request.utf8))

        #expect(answer == .init(reply: .refused(why)))
        #expect(screenshotter.calls.isEmpty)
    }

    @Test("a panel request without the field it needs is refused, and the panel isn't asked")
    func panelMissingField() async {
        let answer = await server().reply(to: Data(#"{"version":1,"command":"panel.showMore","project":"shop"}"#.utf8))

        #expect(answer == .init(reply: .refused("the control command `panel.showMore` needs its `kind`")))
        #expect(panel.calls.isEmpty)
    }

    @Test("a request of another version, an unknown command or no JSON is refused with a reply that says so", arguments: [
        (#"{"version":2,"command":"app.status"}"#,
         "the shipyard command speaks control version 2 and the app version 1: reinstall shipyard so both come from one build"),
        (#"{"version":1,"command":"app.spin"}"#, "the app doesn't know the control command `app.spin`"),
        ("status please", "the request isn't a control request"),
    ])
    func refused(request: String, why: String) async {
        let answer = await server().reply(to: Data(request.utf8))

        #expect(answer == .init(reply: .refused(why)))
    }

    // MARK: - The socket

    @Test("the socket replaces a leftover file, is the user's own, answers the client, and is gone after stop")
    func socket() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Left by an app that crashed.
        try Data().write(to: socket)
        let server = server(socket: socket)
        let client = ControlClient(socket: socket, transport: UnixSocketTransport())

        try server.start()
        var info = stat()
        #expect(stat(socket.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)

        // The client blocks while it waits, so it runs off the main actor the server answers on.
        let status = await Task.detached { client.send(.appStatus(json: true)) }.value
        #expect(status == .success(.done(Self.status.json)))
        let quit = await Task.detached { client.send(.appQuit) }.value
        #expect(quit == .success(.done("shipyard quit\n")))
        for _ in 0..<200 where quitter.quits == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(quitter.quits == 1)

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: socket.path))
        let after = await Task.detached { client.send(.appStatus(json: false)) }.value
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
        _ = UnixSocket.writeAll(impatient, ControlRequest.appStatus(json: false).encoded())
        close(impatient)
        try await Task.sleep(nanoseconds: 50_000_000)

        let client = ControlClient(socket: socket, transport: UnixSocketTransport())
        let status = await Task.detached { client.send(.appStatus(json: false)) }.value
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
