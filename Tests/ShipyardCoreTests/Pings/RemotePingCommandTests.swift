import Foundation
@testable import ShipyardCommand
import ShipyardConfig
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

/// `shipyard` on a machine without the app, as an agent there runs it
/// through `ShipyardCLI.run` with the `Unfiled` filing its build picks:
/// pings saved as given for the Mac to file, the Herdr pane they came
/// from, a day's life, and `ping list --json`. The same commands with the
/// Mac's filing (`ProjectFiling`) keep 0.0.5's behaviour.
@Suite("The ping command on a machine without the app")
struct RemotePingCommandTests {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-remote-\(UUID().uuidString)", isDirectory: true)
    /// The store as read at `now`, the time the commands run at by default.
    var store: PingStore { PingStore(directory: root.appendingPathComponent("pings", isDirectory: true), now: { Self.now }) }
    var configURL: URL { root.appendingPathComponent("config.toml") }
    /// The Mac's filing, against `configURL`.
    var macFiling: ProjectFiling { ProjectFiling(configURL: configURL, repositories: ResolvedRepositoriesStore(directory: root)) }
    static let folder = URL(fileURLWithPath: "/work/shop", isDirectory: true)
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    /// Runs `shipyard <arguments>` at `now` in the build whose filing is
    /// `filing` (a machine without the app's, by default), in a working
    /// folder whose `origin` is `origin`, in Herdr pane `herdrPane`.
    @discardableResult
    func shipyard(
        _ arguments: String...,
        filing: any PingFiling = Unfiled(),
        origin: String? = nil,
        herdrPane: String? = nil,
        at now: Date = Self.now
    ) -> CommandResult {
        ShipyardCLI.run(
            arguments,
            table: .commands(filing: filing, store: store),
            environment: CommandEnvironment(
                workingDirectory: Self.folder,
                variables: herdrPane.map { ["HERDR_PANE_ID": $0] } ?? [:],
                git: FakeGitRemote(origin.map { [Self.folder: $0] } ?? [:])
            ),
            now: now
        )
    }

    /// The one stored ping.
    func stored() throws -> Ping {
        let all = store.all()
        try #require(all.count == 1, "\(all)")
        return all[0]
    }

    // MARK: - Where pings live

    @Test("without the app pings live in the XDG data directory, ~/.local/share without it; on the Mac beside the app's state")
    func storeLocation() {
        let home = URL(fileURLWithPath: "/home/agent", isDirectory: true)
        #expect(PingStore.directoryWithoutTheApp(environment: ["XDG_DATA_HOME": "/data"], home: home).path == "/data/shipyard/pings")
        #expect(PingStore.directoryWithoutTheApp(environment: [:], home: home).path == "/home/agent/.local/share/shipyard/pings")
        #expect(PingStore.directoryWithoutTheApp(environment: ["XDG_DATA_HOME": ""], home: home).path == "/home/agent/.local/share/shipyard/pings")
        #expect(PingStore.directoryWithoutTheApp(environment: ["XDG_DATA_HOME": "data"], home: home).path == "/home/agent/.local/share/shipyard/pings")
        #expect(PingStore.appDirectory(in: URL(fileURLWithPath: "/support", isDirectory: true)).path == "/support/Pings")
    }

    @Test("a ping is one file in the store, as on the Mac")
    func oneFilePerPing() throws {
        shipyard("ping", "First", "--id", "first")
        shipyard("ping", "Second", "--id", "second")

        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
        #expect(files == ["first.json", "second.json"])
    }

    // MARK: - Saved as given

    @Test("without a configuration, a ping keeps its working folder's repository, prints its id and expires a day later")
    func savedByOrigin() throws {
        let result = shipyard("ping", "Which cache?", "--id", "cache", origin: "git@github.com:yahyabedirhan/shop.git")

        #expect(result == CommandResult(output: "cache\n"))
        let ping = try stored()
        #expect(ping.repository == "yahyabedirhan/shop")
        #expect(ping.projects == [])
        #expect(ping.sent == Self.now)
        #expect(ping.expires == Self.now.addingTimeInterval(Self.day))
    }

    @Test("--repo names the repository instead of origin")
    func savedByRepo() throws {
        #expect(shipyard("ping", "Ready", "--repo", "yahyabedirhan/blog", origin: "git@github.com:yahyabedirhan/shop.git").status == 0)
        #expect(try stored().repository == "yahyabedirhan/blog")
    }

    @Test("--project is kept as given, whatever projects exist, and without a repository, as on the Mac")
    func projectAsGiven() throws {
        let result = shipyard("ping", "Ready", "--project", "shop", origin: "git@github.com:yahyabedirhan/shop.git")

        #expect(result.status == 0)
        let ping = try stored()
        #expect(ping.projects == ["shop"])
        #expect(ping.repository == nil)
    }

    @Test("with no --repo, --project or origin, the ping is still saved")
    func savedWithNothing() throws {
        let result = shipyard("ping", "Done", "--id", "done")

        #expect(result == CommandResult(output: "done\n"))
        let ping = try stored()
        #expect(ping.repository == nil)
        #expect(ping.projects == [])
    }

    @Test("an origin that isn't owner/name is no repository, and the ping is still saved")
    func unreadableOrigin() throws {
        #expect(shipyard("ping", "Done", origin: "/srv/repos/shop").status == 0)
        #expect(try stored().repository == nil)
    }

    @Test("a configuration is never read without the app: one that doesn't read, or one no project of which watches the repository, doesn't stop a ping")
    func configurationNotRead() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[[projects]\nname = ".utf8).write(to: configURL)
        #expect(shipyard("ping", "Broken config", "--id", "one").status == 0)

        try Data("[[projects]]\nname = \"blog\"\nrepositories = [\"yahyabedirhan/blog\"]\n".utf8).write(to: configURL)
        #expect(shipyard("ping", "Unwatched", "--id", "two", origin: "https://github.com/yahyabedirhan/shop").status == 0)
        #expect(store.ping(id: "two")?.projects == [])
        #expect(store.ping(id: "two")?.repository == "yahyabedirhan/shop")
    }

    // MARK: - The Herdr pane

    @Test("sent from a Herdr pane without an action, clicking it focuses that pane")
    func herdrPaneWithoutTheFlag() throws {
        #expect(shipyard("ping", "Which cache?", herdrPane: "w1:p3").status == 0)
        #expect(try stored().action == .herdr("w1:p3"))
    }

    @Test("an action the agent gives stays its action, from a Herdr pane too")
    func givenActionWins() throws {
        #expect(shipyard("ping", "PR ready", "--open", "https://github.com/yahyabedirhan/shop/pull/7", herdrPane: "w1:p3").status == 0)
        #expect(try stored().action == .url(URL(string: "https://github.com/yahyabedirhan/shop/pull/7")!))
    }

    @Test("outside Herdr, a ping without an action has none")
    func outsideHerdr() throws {
        #expect(shipyard("ping", "Done", herdrPane: "  ").status == 0)
        #expect(try stored().action == nil)
    }

    // MARK: - Replace

    @Test("sending an id again replaces it: its age and its day start again, and its instance stays")
    func replace() throws {
        shipyard("ping", "Building", "--id", "build")
        let first = try stored()
        let later = Self.now.addingTimeInterval(3600)

        #expect(shipyard("ping", "Built", "--id", "build", at: later) == CommandResult(output: "build\n"))

        let replaced = try stored()
        #expect(replaced.title == "Built")
        #expect(replaced.sent == later)
        #expect(replaced.instance == first.instance)
        #expect(replaced.expires == later.addingTimeInterval(Self.day))
        // The list the Mac reads carries the replace's time, so its row is aged from it.
        let list = try PingList.decode(shipyard("ping", "list", "--json", at: later).output)
        #expect(list.pings.map(\.sent) == [later])
    }

    // MARK: - A day's life

    @Test("a ping is listed until a day after its sending, then it's gone from the store")
    func expiry() throws {
        shipyard("ping", "Which cache?", "--id", "cache")

        let justBefore = try PingList.decode(shipyard("ping", "list", "--json", at: Self.now.addingTimeInterval(Self.day - 1)).output)
        #expect(justBefore.pings.map(\.id) == ["cache"])

        let after = try PingList.decode(shipyard("ping", "list", "--json", at: Self.now.addingTimeInterval(Self.day)).output)
        #expect(after.pings.isEmpty)
        #expect(store.all().isEmpty)
    }

    @Test("a replace keeps a ping a day from the replace")
    func replaceRenews() throws {
        shipyard("ping", "Building", "--id", "build")
        shipyard("ping", "Still building", "--id", "build", at: Self.now.addingTimeInterval(Self.day - 60))

        let list = try PingList.decode(shipyard("ping", "list", "--json", at: Self.now.addingTimeInterval(Self.day + 60)).output)
        #expect(list.pings.map(\.title) == ["Still building"])
    }

    @Test("an expired ping can't be withdrawn, and its id sent again is a new ping")
    func expiredIsGone() throws {
        shipyard("ping", "Which cache?", "--id", "cache")
        let first = try stored()
        let later = Self.now.addingTimeInterval(Self.day + 1)

        #expect(shipyard("ping", "withdraw", "cache", at: later).status == CommandResult.failedStatus)

        shipyard("ping", "Which cache, again?", "--id", "cache", at: later)
        let again = try stored()
        #expect(again.sent == later)
        #expect(again.instance != first.instance)
    }

    @Test("list never shows an expired ping, even one the store couldn't remove")
    func expiredNeverListed() throws {
        try store.save(Ping(id: "old", title: "Old", projects: [], sent: Self.now, expires: Self.now.addingTimeInterval(-1)))
        let list = PingCommand.list(["--json"], store: store, now: Self.now)
        #expect(try PingList.decode(list.output).pings.isEmpty)
    }

    // MARK: - ping list --json

    @Test("list --json prints the contract on one line, newest first, with every field a ping is sent with and no expiry")
    func listContract() throws {
        shipyard("ping", "Older", "--id", "older", "--from", "claude", "--body", "more", origin: "git@github.com:yahyabedirhan/shop.git")
        shipyard("ping", "Newer", "--id", "newer", "--project", "blog", at: Self.now.addingTimeInterval(60))

        let result = shipyard("ping", "list", "--json", at: Self.now.addingTimeInterval(120))

        #expect(result.status == 0)
        #expect(result.error.isEmpty)
        #expect(result.output.hasSuffix("}\n"))
        #expect(result.output.filter { $0 == "\n" }.count == 1)
        #expect(!result.output.contains("expires"))
        let list = try PingList.decode(result.output)
        #expect(list.version == PingList.currentVersion)
        #expect(list.shipyardVersion == ShipyardVersion.current)
        #expect(list.truncated == false)
        #expect(list.pings.map(\.id) == ["newer", "older"])
        #expect(list.pings[0].projects == ["blog"])
        #expect(list.pings[1].repository == "yahyabedirhan/shop")
        #expect(list.pings[1].sender == "claude")
        #expect(list.pings[1].body == "more")
        #expect(list.pings[1].instance != nil)
    }

    @Test("an empty store lists no pings")
    func emptyList() throws {
        let list = try PingList.decode(shipyard("ping", "list", "--json").output)
        #expect(list.pings.isEmpty)
        #expect(list.truncated == false)
    }

    @Test("list --json is capped, saying it stopped early")
    func listCapped() throws {
        for index in 0...PingList.maxPings {
            try store.save(Ping(id: "p\(index)", title: "Ping \(index)", projects: [], sent: Self.now.addingTimeInterval(Double(index)),
                                expires: Self.now.addingTimeInterval(Self.day)))
        }

        let list = try PingList.decode(shipyard("ping", "list", "--json").output)

        #expect(list.pings.count == PingList.maxPings)
        #expect(list.truncated)
        #expect(list.pings.first?.id == "p\(PingList.maxPings)")
    }

    @Test("list without --json, or with more, is exit 2")
    func listNeedsJSON() {
        #expect(shipyard("ping", "list").status == CommandResult.usageStatus)
        #expect(shipyard("ping", "list", "--json", "extra").status == CommandResult.usageStatus)
    }

    // MARK: - The Mac's filing stays as it was

    @Test("with the Mac's filing a ping is filed against the configuration and never expires")
    func macFiles() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[[projects]]\nname = \"shop\"\nrepositories = [\"yahyabedirhan/shop\"]\n".utf8).write(to: configURL)

        #expect(shipyard("ping", "Ready", filing: macFiling, origin: "git@github.com:yahyabedirhan/shop.git", herdrPane: "w1:p3").status == 0)

        let ping = try stored()
        #expect(ping.projects == ["shop"])
        #expect(ping.expires == nil)
        #expect(ping.action == nil)
        #expect(shipyard("ping", "list", "--json", filing: macFiling, at: Self.now.addingTimeInterval(30 * Self.day)).output.contains("\"Ready\""))
        #expect(store.all().count == 1)
    }

    @Test("with the Mac's filing a ping no project watches is still refused, and one with no configuration too")
    func macRefuses() {
        let unwatched = shipyard("ping", "Ready", filing: macFiling, origin: "git@github.com:yahyabedirhan/shop.git")
        #expect(unwatched.status == CommandResult.failedStatus)
        #expect(unwatched.error == "shipyard ping: no project watches `yahyabedirhan/shop`; pass --project <name> to file it under one; config.toml has no projects yet\n")
        #expect(shipyard("ping", "Ready", "--project", "shop", filing: macFiling).status == CommandResult.failedStatus)
        #expect(store.all().isEmpty)
    }
}
