import Foundation
import ShipyardCLISettings
import ShipyardCommand
import ShipyardNotices
import Testing

/// `shipyard notify` as an agent runs it on a machine without the app,
/// through `ShipyardCLI.run` with that build's table: `cli.toml`'s
/// `[notify]` decides the route, and with `app-machine` set the notice goes
/// to the Mac over the tailnet, one HTTP request answered with the app's
/// verdict. A recording HTTP stands in for the network. Whether the app
/// shows it is the app's to say (`TailnetNoticeTests`).
@Suite("The notify command over the tailnet")
struct TailnetNotifyCommandTests {
    static let folder = URL(fileURLWithPath: "/work/shop", isDirectory: true)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-notify-\(UUID().uuidString)", isDirectory: true)
    var settings: CLISettingsFile { CLISettingsFile(url: root.appendingPathComponent("cli.toml")) }

    /// A working folder's `origin`.
    struct Git: GitRemoteLookup {
        func origin(in folder: URL) -> String? { "git@github.com:owner/shop.git" }
    }

    /// Writes `cli.toml`.
    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settings.url)
    }

    /// Runs `shipyard <arguments>` in the build without the app, over `http`.
    func shipyard(_ arguments: [String], http: RecordingHTTP, poll: RecordingRoute = RecordingRoute()) -> CommandResult {
        var table = CommandTable()
        table.add(NoticeCommands.entries(route: RemoteNoticeRoute(settings: settings, http: http, poll: poll)))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: Self.folder, variables: [:], git: Git()),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("with app-machine set the notice is posted to the Mac as its JSON, and `shown` printed once the app showed it")
    func shown() throws {
        try write("[notify]\napp-machine = \"my-mac\"\n")
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))

        let result = shipyard(["notify", "Tests running", "--body", "12 of 40 passed", "--from", "claude"], http: http)

        #expect(result == CommandResult(output: "shown\n"))
        let post = try #require(http.posts.current.first)
        #expect(http.posts.current.count == 1)
        #expect(post.url.absoluteString == "http://my-mac:47420/notify")
        #expect(post.timeout == 3)
        #expect(String(decoding: post.body, as: UTF8.self)
            == #"{"body":"12 of 40 passed","from":"claude","repository":"owner\/shop","title":"Tests running"}"#)
    }

    @Test("a withdrawal goes the same way, as its own JSON, and prints `withdrawn` once the app did it")
    func withdraw() throws {
        try write("[notify]\napp-machine = \"my-mac\"\n")
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))

        let result = shipyard(["notify", "withdraw", "tests"], http: http)

        #expect(result == CommandResult(output: "withdrawn\n"))
        #expect(http.posts.current.map { String(decoding: $0.body, as: UTF8.self) } == [#"{"withdraw":"tests"}"#])
    }

    @Test("a request carrying an image is given longer to cross: a second more for each megabyte past the first")
    func imageTimeout() {
        #expect(TailnetWire.timeout(forBodyOf: 300) == 3)
        #expect(TailnetWire.timeout(forBodyOf: 1 << 20) == 3)
        #expect(TailnetWire.timeout(forBodyOf: 7 << 20) == 9)
    }

    @Test("the scheme and port come from cli.toml, as tailscale serve exposes the app's port")
    func schemeAndPort() throws {
        try write("[notify]\napp-machine = \"my-mac.tail1234.ts.net\"\nscheme = \"https\"\nport = 443\n")
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))

        _ = shipyard(["notify", "Done"], http: http)

        #expect(http.posts.current.map(\.url.absoluteString) == ["https://my-mac.tail1234.ts.net:443/notify"])
    }

    @Test("the app's refusal exits 1 with its reason, whatever the HTTP status it came with", arguments: [200, 403])
    func refused(status: Int) throws {
        try write("[notify]\napp-machine = \"my-mac\"\n")
        let http = RecordingHTTP(.answered(status: status, body: Data(#"{"refused":"notices are off for project `shop`"}"#.utf8)))

        let result = shipyard(["notify", "Done"], http: http)

        #expect(result == CommandResult(error: "shipyard notify: notices are off for project `shop`\n", status: 1))
    }

    @Test("an app machine that can't be reached, doesn't answer in time, or answers without a verdict exits 1 saying so", arguments: [
        (RecordingHTTP.Outcome.unreachable("Could not connect to the server."),
         "couldn't reach the app machine `my-mac` at http://my-mac:47420, so this notice wasn't shown: Could not connect to the server."),
        (.timedOut, "the app machine `my-mac` didn't answer within 3 seconds, so this notice may not have been shown"),
        (.answered(status: 502, body: Data("Bad Gateway".utf8)),
         "the app machine `my-mac` answered HTTP 502 without a verdict, so this notice wasn't shown; "
            + "check that shipyard runs there with [notify] listen = true, behind tailscale serve"),
    ])
    func unreachable(outcome: RecordingHTTP.Outcome, line: String) throws {
        try write("[notify]\napp-machine = \"my-mac\"\n")

        let result = shipyard(["notify", "Done"], http: RecordingHTTP(outcome))

        #expect(result == CommandResult(error: "shipyard notify: \(line)\n", status: 1))
    }

    @Test("without app-machine, or without cli.toml, the notice takes the poll route instead, and nothing goes over the tailnet", arguments: [nil, "", "[notify]\nport = 8080\n"])
    func unset(text: String?) throws {
        if let text { try write(text) }
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))
        let poll = RecordingRoute()

        let result = shipyard(["notify", "Done"], http: http, poll: poll)

        #expect(result == CommandResult(output: PluginNoticeRoute.queuedLine + "\n"))
        #expect(poll.notices.current == [.show(Notice(title: "Done", repository: "owner/shop"))])
        #expect(http.posts.current.isEmpty)
    }

    @Test("a cli.toml that doesn't read exits 1 naming it, and sends nothing either way")
    func malformed() throws {
        try write("[notify]\napp-machin = \"my-mac\"\n")
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))
        let poll = RecordingRoute()

        let result = shipyard(["notify", "Done"], http: http, poll: poll)
        #expect(poll.notices.current.isEmpty)

        #expect(result.status == 1)
        #expect(result.error.hasPrefix("shipyard notify: \(settings.url.path) doesn't read (unknown setting `notify.app-machin`"), "\(result.error)")
        #expect(http.posts.current.isEmpty)
    }

    @Test("arguments that don't read exit 2 before cli.toml is read")
    func misread() throws {
        try write("[notify]\napp-machine = \"my-mac\"\n")
        let http = RecordingHTTP(.answered(status: 200, body: Data(#"{"shown":true}"#.utf8)))

        let result = shipyard(["notify", "Done", "--colour", "red"], http: http)

        #expect(result == CommandResult(error: "shipyard notify: unknown option `--colour`\n", status: 2))
        #expect(http.posts.current.isEmpty)
    }
}

/// The poll route, standing in for the herdr-shipyard plugin: records each
/// notice and queues it.
final class RecordingRoute: NoticeRoute {
    let notices = Locked<[NoticeRequest]>([])

    func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict {
        notices.withValue { $0.append(request) }
        return .queued
    }
}

/// A `NoticeHTTP` standing in for the network: records each post and
/// answers with the outcome it was given.
final class RecordingHTTP: NoticeHTTP {
    typealias Outcome = NoticeHTTPOutcome

    struct Post {
        var body: Data
        var url: URL
        var timeout: TimeInterval
    }

    let posts = Locked<[Post]>([])
    private let outcome: Outcome

    init(_ outcome: Outcome) { self.outcome = outcome }

    func post(_ body: Data, to url: URL, timeout: TimeInterval) -> NoticeHTTPOutcome {
        posts.withValue { $0.append(Post(body: body, url: url, timeout: timeout)) }
        return outcome
    }
}
