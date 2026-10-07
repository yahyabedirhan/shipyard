import Foundation
@testable import ShipyardCommand
import ShipyardConfig
@testable import ShipyardCore
@testable import ShipyardPings
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
    /// The agent's working folder, a fake one: `origin` says its remote.
    static let folder = URL(fileURLWithPath: "/work/shop", isDirectory: true)
    let environment = CommandEnvironment(workingDirectory: Self.folder, variables: [:], git: FakeGitRemote())

    /// The Mac's filing, as `main.swift` builds it, over a `config.toml`
    /// holding `text` and the resolved lists `resolved`, in a fresh
    /// temporary folder.
    private func filing(_ text: String = twoProjects, resolved: [String: [String]] = [:]) throws -> ProjectFiling {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-filing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configURL = folder.appendingPathComponent("config.toml")
        try Data(text.utf8).write(to: configURL)
        let repositories = ResolvedRepositoriesStore(directory: folder)
        if !resolved.isEmpty { try repositories.record(resolved) }
        return ProjectFiling(configURL: configURL, repositories: repositories)
    }

    private func ping(
        _ arguments: String...,
        config: String = twoProjects,
        origin: String? = nil,
        resolved: [String: [String]] = [:],
        id: String = "k7qm2x"
    ) throws -> CommandResult {
        PingCommand.run(
            arguments,
            environment: CommandEnvironment(
                workingDirectory: Self.folder,
                variables: [:],
                git: FakeGitRemote(origin.map { [Self.folder: $0] } ?? [:])
            ),
            filing: try filing(config, resolved: resolved),
            store: store,
            now: Harness.now,
            newID: { id }
        )
    }

    /// The stored pings, each without its `instance` (made up at random,
    /// tested end to end in `PingIDTests`).
    private var storedWithoutInstance: [Ping] {
        store.all().map { ping in
            var ping = ping
            #expect(ping.instance != nil)
            ping.instance = nil
            return ping
        }
    }

    @Test("a ping with --project is stored under it, and only its id printed: the Mac numbers it")
    func sendsAPing() throws {
        let result = try ping("Ready for review", "--project", "shop")

        #expect(result == CommandResult(output: "k7qm2x\n"))
        #expect(storedWithoutInstance == [Ping(id: "k7qm2x", title: "Ready for review", projects: ["shop"], sent: Harness.now)])
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

    @Test("without a flag, the working folder's origin remote picks the repository, and the ping is filed under its project")
    func filedByTheWorkingFolder() throws {
        let result = try ping("Ready for review", origin: "git@github.com:yahyabedirhan/shop.git")

        #expect(result == CommandResult(output: "k7qm2x\n"))
        #expect(storedWithoutInstance == [Ping(id: "k7qm2x", title: "Ready for review", projects: ["shop"], sent: Harness.now, repository: "yahyabedirhan/shop")])
    }

    @Test("a repository two projects watch files the ping under both, matching its name ignoring case, spelled as the configuration does")
    func filedUnderEveryWatcher() throws {
        let config = twoProjects + """

            [[projects]]
            name = "everything"
            repositories = ["yahyabedirhan/blog", "YahyaBedirhan/Shop"]

            """
        #expect(try ping("Ready", config: config, origin: "https://github.com/yahyabedirhan/shop").status == 0)

        let filed = try #require(store.all().first)
        #expect(filed.projects == ["shop", "everything"])
        #expect(filed.repository == "yahyabedirhan/shop")
    }

    @Test("--repo overrides the working folder")
    func repoOverrides() throws {
        #expect(try ping("Published", "--repo", "yahyabedirhan/blog", origin: "git@github.com:yahyabedirhan/shop.git").status == 0)
        #expect(store.all().map(\.projects) == [["blog"]])
        #expect(store.all().map(\.repository) == ["yahyabedirhan/blog"])
    }

    @Test("--repo works outside a git folder")
    func repoOutsideGit() throws {
        #expect(try ping("Published", "--repo", "yahyabedirhan/blog").status == 0)
        #expect(store.all().map(\.projects) == [["blog"]])
    }

    @Test("--project files the ping under that project alone, with no repository, whatever the working folder")
    func projectOverrides() throws {
        #expect(try ping("Ready", "--project", "blog", origin: "git@github.com:yahyabedirhan/shop.git").status == 0)
        #expect(store.all().map(\.projects) == [["blog"]])
        #expect(store.all().map(\.repository) == [nil])
    }

    @Test("--repo and --project together are a usage error")
    func repoAndProject() throws {
        let result = try ping("Ready", "--repo", "yahyabedirhan/shop", "--project", "shop")

        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: pass --repo or --project, not both\n")
        #expect(store.all().isEmpty)
    }

    @Test("--repo takes owner/name only")
    func repoMustBeASlug() throws {
        for value in ["shop", "yahyabedirhan/*", "https://github.com/yahyabedirhan/shop"] {
            let result = try ping("Ready", "--repo", value)
            #expect(result.status == 2, "\(value)")
            #expect(result.error == "shipyard ping: `--repo` takes a repository as owner/name, not `\(value)`\n")
        }
        #expect(store.all().isEmpty)
    }

    @Test("a repository a group or owner/* brought in matches once the app has resolved it")
    func resolvedRepository() throws {
        let config = """
            [[projects]]
            name = "mine"
            repositories = ["owned"]

            [[projects]]
            name = "org"
            repositories = ["some-org/*"]

            """
        let unresolved = try ping("Ready", config: config, origin: "git@github.com:some-org/app.git")
        #expect(unresolved.status == 1)

        let result = try ping(
            "Ready",
            config: config,
            origin: "git@github.com:some-org/app.git",
            resolved: ["mine": ["yahyabedirhan/shop"], "org": ["Some-Org/app"], "gone": ["some-org/app"]]
        )
        #expect(result.status == 0)
        #expect(store.all().map(\.projects) == [["org"]])
        #expect(store.all().map(\.repository) == ["Some-Org/app"])
    }

    @Test("an unwatched repository fails, listing the projects, and stores nothing")
    func unwatchedRepository() throws {
        for result in [
            try ping("Ready", origin: "git@github.com:someone/else.git"),
            try ping("Ready", "--repo", "someone/else"),
        ] {
            #expect(result.status == 1)
            #expect(result.output.isEmpty)
            #expect(result.error == "shipyard ping: no project watches `someone/else`; pass --project <name> to file it under one; the projects are `shop`, `blog`\n")
        }
        #expect(store.all().isEmpty)
    }

    @Test("a working folder that isn't a git repository, or has no origin remote, fails with the projects listed")
    func noRemote() throws {
        let result = try ping("Ready")

        #expect(result.status == 1)
        #expect(result.error == "shipyard ping: the working folder (/work/shop) isn't a git repository with a remote `origin` to file the ping by; pass --repo <owner/name> or --project <name>; the projects are `shop`, `blog`\n")
        #expect(store.all().isEmpty)
    }

    @Test("an origin remote that doesn't name owner/name fails with the projects listed")
    func remoteWithoutRepository() throws {
        let result = try ping("Ready", origin: "/srv/git/shop")

        #expect(result.status == 1)
        #expect(result.error == "shipyard ping: the working folder's remote `origin` (/srv/git/shop) doesn't name a repository as owner/name; pass --repo <owner/name> or --project <name>; the projects are `shop`, `blog`\n")
    }

    @Test(
        "a remote's URL reads as owner/name in each form git writes it",
        arguments: [
            ("https://github.com/yahyabedirhan/shop.git", "yahyabedirhan/shop"),
            ("https://github.com/yahyabedirhan/shop", "yahyabedirhan/shop"),
            ("https://github.com/yahyabedirhan/shop/", "yahyabedirhan/shop"),
            ("https://token@github.com/yahyabedirhan/shop.git", "yahyabedirhan/shop"),
            ("git@github.com:yahyabedirhan/shop.git", "yahyabedirhan/shop"),
            ("github.com:yahyabedirhan/my.site", "yahyabedirhan/my.site"),
            ("ssh://git@github.com:22/yahyabedirhan/shop.git", "yahyabedirhan/shop"),
            ("git://github.com/yahyabedirhan/shop", "yahyabedirhan/shop"),
        ]
    )
    func remoteForms(url: String, slug: String) {
        #expect(GitRemote.repository(fromURL: url) == slug)
    }

    @Test("a local remote, or one that names no owner/name, reads as none", arguments: ["/srv/git/shop", "file:///srv/git/shop", "shop", "https://github.com/shop", "https://gitlab.com/group/sub/shop", "git@host:", ""])
    func remoteWithoutSlug(url: String) {
        #expect(GitRemote.repository(fromURL: url) == nil)
    }

    @Test("a missing or empty title, a second title, an unknown flag or a flag without its value is a usage error")
    func usageErrors() throws {
        let cases: [([String], String)] = [
            (["--project", "shop"], "shipyard ping: give the ping a title: shipyard ping \"<title>\" [options] (shipyard ping --help lists them)"),
            (["  ", "--project", "shop"], "shipyard ping: give the ping a title: shipyard ping \"<title>\" [options] (shipyard ping --help lists them)"),
            (["Ready", "now", "--project", "shop"], "shipyard ping: one title only; quote it: shipyard ping \"Ready now\""),
            (["Ready", "--projcet", "shop"], "shipyard ping: unknown option `--projcet`"),
            (["Ready", "--project"], "shipyard ping: `--project` needs a value"),
            (["Ready", "--repo"], "shipyard ping: `--repo` needs a value"),
        ]
        for (arguments, message) in cases {
            let result = PingCommand.run(
                arguments,
                environment: environment,
                filing: try filing(),
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
            filing: try filing(),
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
        #expect(help.output.contains("shipyard ping \"<title>\" [--body <text>] [--from <label>]"))

        let bare = harness.cli()
        #expect(bare.status == 2)
        #expect(bare.error.contains("[--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]"))

        let unknown = harness.cli("pnig", "Ready")
        #expect(unknown.status == 2)
        #expect(unknown.error.hasPrefix("shipyard: unknown command `pnig`\n"))
    }

    @Test("--version prints shipyard's version")
    func version() throws {
        let result = try Harness(config: twoProjects).cli("--version")
        #expect(result == CommandResult(output: "shipyard \(ShipyardVersion.current)\n"))
    }

    @Test("ping help prints the ping usage, with --id, withdraw and --; the main help lists withdraw too")
    func pingHelp() throws {
        let harness = try Harness(config: twoProjects)
        let result = harness.cli("ping", "--help")
        #expect(result.status == 0)
        #expect(result.output.hasPrefix("usage: shipyard ping \"<title>\" [--body <text>] [--from <label>] [--id <id>]\n"))
        #expect(result.output.contains("shipyard ping withdraw <id>"))
        #expect(result.output.contains("shipyard ping -- withdraw"))
        #expect(harness.cli("--help").output.contains("shipyard ping withdraw <id>"))
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

    // MARK: - Which config.toml

    /// `shipyard <arguments>` as the Mac's `main.swift` assembles it, in an
    /// agent's shell whose environment is `shell` and whose home is
    /// `home`: the configuration file is the one `ConfigurationLocation` finds
    /// beside `harness`'s app state, the folder the app writes for the CLI.
    private func shipyard(_ arguments: String..., in harness: Harness, shell: [String: String], home: URL) -> CommandResult {
        let filing = ProjectFiling(
            configURL: ConfigurationLocation.current(environment: shell, home: home, support: harness.stateDirectory),
            repositories: harness.repositoriesStore
        )
        return ShipyardCLI.run(
            arguments,
            table: .commands(filing: filing, store: harness.pingStore),
            environment: CommandEnvironment(workingDirectory: harness.workingFolder, variables: shell, git: FakeGitRemote()),
            now: harness.clock.now
        )
    }

    /// A folder for an agent's own `XDG_CONFIG_HOME`, holding a
    /// `shipyard/config.toml` with only the project `elsewhere`.
    private func shellConfigHome() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-shell-\(UUID().uuidString)", isDirectory: true)
        let config = folder.appendingPathComponent("shipyard/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[[projects]]\nname = \"elsewhere\"\nrepositories = [\"o/elsewhere\"]\n".utf8).write(to: config)
        return folder
    }

    @Test("once the app has run, a ping files against the config.toml it reads, whatever XDG_CONFIG_HOME the agent's shell sets")
    func appsConfiguration() async throws {
        let harness = try Harness(config: twoProjects)
        await harness.shipyard.start()
        let shell = ["XDG_CONFIG_HOME": try shellConfigHome().path]
        let home = harness.workingFolder

        let filed = shipyard("ping", "Ready", "--project", "shop", in: harness, shell: shell, home: home)
        let refused = shipyard("ping", "Ready", "--project", "elsewhere", in: harness, shell: shell, home: home)

        #expect(filed.status == 0, "\(filed.error)")
        #expect(harness.pingStore.all().map(\.projects) == [["shop"]])
        #expect(refused.error == "shipyard ping: no project is named `elsewhere`; the projects are `shop`, `blog`\n")
    }

    @Test("before the app has ever run, a ping files against the config.toml the agent's shell points at")
    func ownLookupBeforeTheApp() throws {
        let harness = try Harness(config: twoProjects)
        let shell = ["XDG_CONFIG_HOME": try shellConfigHome().path]

        let filed = shipyard("ping", "Ready", "--project", "elsewhere", in: harness, shell: shell, home: harness.workingFolder)

        #expect(filed.status == 0, "\(filed.error)")
        #expect(harness.pingStore.all().map(\.projects) == [["elsewhere"]])
    }

    @Test("a ping only projects that hide pings would list is refused, naming them, and stores nothing; one any project shows is filed under all of them")
    func pingNoProjectShows() throws {
        let harness = try Harness(config: """
            [defaults.pings]
            show = false

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "store"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog", "yahyabedirhan/shop"]
            pings = { show = true }

            [[projects]]
            name = "docs"
            repositories = ["yahyabedirhan/docs"]

            """)

        let hidden = harness.cli("ping", "Ready", "--repo", "yahyabedirhan/docs")
        #expect(hidden.status == 1)
        #expect(hidden.output.isEmpty)
        #expect(hidden.error == "shipyard ping: no project shows the ping: `docs` hides pings (pings.show = false); pass --project <name> to file it under one that shows them; the projects that show pings are `blog`\n")

        let named = harness.cli("ping", "Ready", "--project", "shop")
        #expect(named.error == "shipyard ping: no project shows the ping: `shop` hides pings (pings.show = false); pass --project <name> to file it under one that shows them; the projects that show pings are `blog`\n")
        #expect(harness.pingStore.all().isEmpty)

        let shown = harness.cli("ping", "Ready", origin: "git@github.com:yahyabedirhan/shop.git")
        #expect(shown.status == 0)
        #expect(harness.pingStore.all().map(\.projects) == [["shop", "store", "blog"]])
    }

    @Test("when every project hides pings, the refusal names each that would list it and says none shows them")
    func noProjectShowsPings() throws {
        let harness = try Harness(config: """
            [defaults.pings]
            show = false

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "store"
            repositories = ["yahyabedirhan/shop"]

            """)

        let result = harness.cli("ping", "Ready", origin: "git@github.com:yahyabedirhan/shop.git")

        #expect(result.status == 1)
        #expect(result.error == "shipyard ping: no project shows the ping: `shop`, `store` hide pings (pings.show = false); no project shows pings\n")
        #expect(harness.pingStore.all().isEmpty)
    }
}
