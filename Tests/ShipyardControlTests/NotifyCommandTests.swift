import Foundation
import ShipyardCommand
import ShipyardControl
import ShipyardNotices
import Testing

/// `shipyard notify` as an agent runs it on the Mac, through
/// `ShipyardCLI.run` with the Mac's table, an in-memory app at the end of
/// the socket and a recording launcher: the notice it sends, what it
/// prints and how it exits. Whether the notice is shown is the app's to
/// say (`NoticeTests`); its verdict comes back as the reply.
@Suite("The notify command")
struct NotifyCommandTests {
    static let support = URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true)
    static let folder = URL(fileURLWithPath: "/work/shop", isDirectory: true)

    /// A working folder's `origin`, or none.
    struct Git: GitRemoteLookup {
        var origin: String?
        func origin(in folder: URL) -> String? { origin }
    }

    /// Runs `shipyard <arguments>` in the Mac's build, in a checkout whose
    /// `origin` is `origin`, against `transport`.
    func shipyard(
        _ arguments: [String],
        origin: String? = "git@github.com:owner/shop.git",
        transport: FakeTransport,
        launcher: RecordingLauncher = RecordingLauncher()
    ) -> CommandResult {
        var table = CommandTable()
        table.add(NoticeCommands.entries(route: ControlNoticeRoute(
            support: Self.support, transport: transport, processes: FakeProcessTable.agent
        )))
        // `app` is there too, as in the real table, so a launch would show.
        table.add(ControlCommands.entries(
            support: Self.support, launcher: launcher, transport: transport, processes: FakeProcessTable.agent, pause: { _ in }
        ))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: Self.folder, variables: [:], git: Git(origin: origin)),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("a notice goes to the app over control.sock, filed by the checkout's origin, and prints `shown` once the app showed it")
    func shown() throws {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["notify", "Tests running", "--body", "12 of 40 passed", "--from", "claude"], transport: app)

        #expect(result == CommandResult(output: "shown\n"))
        let exchange = try #require(app.exchanges.current.only)
        #expect(exchange.socket == ControlSocket.url(in: Self.support))
        #expect(exchange.timeout == ControlNoticeRoute.timeout)
        #expect(String(decoding: exchange.request, as: UTF8.self) == #"{"command":"notify",\#(FakeProcessTable.wire(place: "/work/shop")),"#
            + #""notice":{"body":"12 of 40 passed","from":"claude","repository":"owner\/shop","title":"Tests running"},"version":2}"#)
    }

    @Test("--project and --repo say where it's filed instead of the checkout, which then needn't be one", arguments: [
        (["notify", "Done", "--project", "my shop"], Notice(title: "Done", project: "my shop")),
        (["notify", "--repo", "owner/blog", "Done"], Notice(title: "Done", repository: "owner/blog")),
        (["notify", "--", "--repo"], nil),
    ])
    func filedBy(arguments: [String], notice: Notice?) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(arguments, origin: nil, transport: app)

        if let notice {
            #expect(result == CommandResult(output: "shown\n"))
            #expect(app.requests == [.notify(notice)])
        } else {
            // After --, a flag's word is the title, and the checkout files it.
            #expect(result.status == 1)
            #expect(app.requests.isEmpty)
        }
    }

    @Test("a notice the app refuses, such as one whose project turned notices off, exits 1 with the app's reason")
    func refused() {
        let app = FakeTransport(reply: .refused("notices are off for project `shop`"))

        let result = shipyard(["notify", "Done"], transport: app)

        #expect(result == CommandResult(error: "shipyard notify: notices are off for project `shop`\n", status: 1))
    }

    @Test("with the app not running it exits 1 saying the notice wasn't shown, and never launches the app")
    func notRunning() {
        let launcher = RecordingLauncher()

        let result = shipyard(["notify", "Done"], transport: .nothingListens, launcher: launcher)

        #expect(result == CommandResult(error: "shipyard notify: shipyard isn't running, so this notice wasn't shown\n", status: 1))
        #expect(launcher.launches.current.isEmpty)
    }

    @Test("an app that doesn't answer in time, or can't be asked, exits 1 saying so")
    func unanswered() {
        #expect(shipyard(["notify", "Done"], transport: FakeTransport { _, _ in .failure(.timedOut) }) == CommandResult(
            error: "shipyard notify: shipyard didn't answer within 5 seconds, so this notice may not have been shown\n", status: 1
        ))
        #expect(shipyard(["notify", "Done"], transport: FakeTransport { _, _ in .failure(.failed("connection reset")) }) == CommandResult(
            error: "shipyard notify: couldn't reach shipyard, so this notice wasn't shown: connection reset\n", status: 1
        ))
    }

    @Test("a checkout with no origin to file by exits 1 and sends nothing")
    func noRepository() {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["notify", "Done"], origin: nil, transport: app)

        #expect(result == CommandResult(
            error: "shipyard notify: the working folder (/work/shop) isn't a git repository with a remote `origin` to file the notice by; "
                + "pass --repo <owner/name> or --project <name>\n",
            status: 1
        ))
        #expect(app.requests.isEmpty)
    }

    @Test("arguments that don't read exit 2 with what's wrong and send nothing", arguments: [
        ([], "give the notice a title: shipyard notify \"<title>\" [options] (shipyard notify --help lists them)"),
        (["  "], "give the notice a title: shipyard notify \"<title>\" [options] (shipyard notify --help lists them)"),
        (["Tests", "running"], "one title only; quote it: shipyard notify \"Tests running\""),
        (["Done", "--sound", "none"], "unknown option `--sound`"),
        (["Done", "--body"], "`--body` needs a value"),
        (["Done", "--repo", "shop"], "`--repo` takes a repository as owner/name, not `shop`"),
        (["Done", "--project", ""], "`--project` takes a project's name"),
        (["Done", "--repo", "owner/shop", "--project", "shop"], "pass --repo or --project, not both"),
    ])
    func misread(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["notify"] + arguments, transport: app)

        #expect(result == CommandResult(error: "shipyard notify: \(line)\n", status: 2))
        #expect(app.requests.isEmpty)
    }

    @Test("--help prints the command's usage and sends nothing; shipyard --help lists it")
    func help() {
        let app = FakeTransport(reply: .done(""))

        let usage = shipyard(["notify", "Done", "--help"], transport: app)
        let all = shipyard(["--help"], transport: app)

        #expect(usage == CommandResult(output: NotifyCommand.usageText))
        #expect(all.output.contains("  notify  show the user a notice"))
        #expect(app.requests.isEmpty)
    }
}
