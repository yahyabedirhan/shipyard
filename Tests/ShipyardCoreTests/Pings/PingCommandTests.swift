import Foundation
@testable import ShipyardCore
import Testing

private let twoProjects = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

/// `shipyard ping` as an agent runs it: arguments, environment,
/// configuration and the ping store in, the text it prints and its exit
/// status out. What the app then shows is in `PingsTests`.
@Suite("The ping command")
struct PingCommandTests {
    let store = PingStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-pings-\(UUID().uuidString)", isDirectory: true))
    let environment = CommandEnvironment(workingDirectory: FileManager.default.temporaryDirectory, variables: [:])

    private func ping(_ arguments: String..., config: String = twoProjects, id: String = "k7qm2x") throws -> CommandResult {
        PingCommand.run(
            arguments,
            environment: environment,
            configuration: try Configuration.decode(config).configuration,
            store: store,
            now: Harness.now,
            newID: { id }
        )
    }

    @Test("a ping with --project is stored under it, and its id printed")
    func sendsAPing() throws {
        let result = try ping("Ready for review", "--project", "shop")

        #expect(result == CommandResult(output: "k7qm2x\n"))
        #expect(store.all() == [Ping(id: "k7qm2x", title: "Ready for review", projects: ["shop"], sent: Harness.now)])
    }

    @Test("the flags can come before the title")
    func flagsFirst() throws {
        #expect(try ping("--project", "blog", "Published").status == 0)
        #expect(store.all().map(\.projects) == [["blog"]])
    }

    @Test("an unknown project fails, listing the projects, and stores nothing")
    func unknownProject() throws {
        let result = try ping("Ready", "--project", "shopp")

        #expect(result.status == 1)
        #expect(result.output.isEmpty)
        #expect(result.error == "shipyard ping: no project is named `shopp`; the projects are `shop`, `blog`\n")
        #expect(store.all().isEmpty)
    }

    @Test("without projects in the configuration, the error says so")
    func noProjects() throws {
        let result = try ping("Ready", "--project", "shop", config: "")

        #expect(result.status == 1)
        #expect(result.error == "shipyard ping: no project is named `shop`; config.toml has no projects yet\n")
    }

    @Test("without --project, it says to name one and lists the projects")
    func projectMissing() throws {
        let result = try ping("Ready")

        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: name the project to file it under with --project <name>; the projects are `shop`, `blog`\n")
        #expect(store.all().isEmpty)
    }

    @Test("a missing or empty title, a second title, an unknown flag or a flag without its value is a usage error")
    func usageErrors() throws {
        let cases: [([String], String)] = [
            (["--project", "shop"], "shipyard ping: give the ping a title: shipyard ping \"<title>\" --project <name>"),
            (["  ", "--project", "shop"], "shipyard ping: give the ping a title: shipyard ping \"<title>\" --project <name>"),
            (["Ready", "now", "--project", "shop"], "shipyard ping: one title only; quote it: shipyard ping \"Ready now\""),
            (["Ready", "--projcet", "shop"], "shipyard ping: unknown option `--projcet`"),
            (["Ready", "--project"], "shipyard ping: `--project` needs a value"),
        ]
        for (arguments, message) in cases {
            let result = PingCommand.run(
                arguments,
                environment: environment,
                configuration: try Configuration.decode(twoProjects).configuration,
                store: store,
                now: Harness.now
            )
            #expect(result.status == 2, "\(arguments)")
            #expect(result.error == message + "\n", "\(arguments)")
        }
        #expect(store.all().isEmpty)
    }

    @Test("a generated id is six readable letters and digits, and new each time")
    func generatedIDs() throws {
        let ids = (0..<20).map { _ in Ping.newID() }
        for id in ids {
            #expect(id.count == 6)
            #expect(id.allSatisfy { Ping.idAlphabet.contains($0) })
        }
        #expect(Set(ids).count > 1)
    }

    @Test("a generated id already stored is drawn again")
    func generatedIDsDoNotCollide() throws {
        try store.save(Ping(id: "aaaaaa", title: "Earlier", projects: ["shop"], sent: Harness.now))
        var drawn = ["aaaaaa", "bbbbbb"].makeIterator()
        let result = PingCommand.run(
            ["Ready", "--project", "shop"],
            environment: environment,
            configuration: try Configuration.decode(twoProjects).configuration,
            store: store,
            now: Harness.now,
            newID: { drawn.next()! }
        )
        #expect(result.output == "bbbbbb\n")
        #expect(store.all().map(\.title) == ["Earlier", "Ready"])
    }
}

/// The `shipyard` command line: its subcommands, its help, and reading the
/// configuration before a ping.
@Suite("The shipyard CLI")
@MainActor
struct ShipyardCLITests {
    @Test("help and no arguments print the usage; an unknown command fails with it")
    func usage() throws {
        let harness = try Harness(config: twoProjects)

        let help = harness.cli("--help")
        #expect(help.status == 0)
        #expect(help.output.contains("shipyard ping \"<title>\" --project <name>"))

        let bare = harness.cli()
        #expect(bare.status == 2)
        #expect(bare.error.contains("shipyard ping \"<title>\" --project <name>"))

        let unknown = harness.cli("pnig", "Ready")
        #expect(unknown.status == 2)
        #expect(unknown.error.hasPrefix("shipyard: unknown command `pnig`\n"))
    }

    @Test("--version prints shipyard's version")
    func version() throws {
        let result = try Harness(config: twoProjects).cli("--version")
        #expect(result == CommandResult(output: "shipyard \(ShipyardVersion.current)\n"))
    }

    @Test("ping help prints the ping usage")
    func pingHelp() throws {
        let result = try Harness(config: twoProjects).cli("ping", "--help")
        #expect(result.status == 0)
        #expect(result.output.hasPrefix("usage: shipyard ping \"<title>\" --project <name>"))
    }

    @Test("a configuration that doesn't read fails the ping with its first problem, storing nothing")
    func brokenConfiguration() throws {
        let harness = try Harness(config: twoProjects + "\n[[projects]]\nname = \"shop\"\nrepositories = [\"o/r\"]\n")

        let result = harness.cli("ping", "Ready", "--project", "shop")

        #expect(result.status == 1)
        #expect(result.error.hasPrefix("shipyard: config.toml doesn't read (line "))
        #expect(result.error.contains("project name `shop` is used twice"))
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("without a configuration file, there are no projects to file under")
    func noConfigurationFile() throws {
        let harness = try Harness()

        let result = harness.cli("ping", "Ready", "--project", "shop")

        #expect(result.status == 1)
        #expect(result.error == "shipyard ping: no project is named `shop`; config.toml has no projects yet\n")
    }
}
