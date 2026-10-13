import Foundation
import ShipyardCommand
import ShipyardControl
import ShipyardNotices
@testable import ShipyardPings
import Testing

/// The `shipyard` router as the Mac's build assembles it: every group its
/// `main.swift` adds, run through `ShipyardCLI.run`. The contract it owns is
/// the command table's: the help is made from it, `help --json` lists it,
/// old names keep working with a warning, and a mistyped group gets the
/// closest one. Each group's own behaviour is its own suite's.
@Suite("The command table")
struct CommandTableTests {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-table-\(UUID().uuidString)", isDirectory: true)
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    var store: PingStore { PingStore(directory: root.appendingPathComponent("pings", isDirectory: true), now: { Self.now }) }

    /// The Mac's table, with pings kept as sent and the app nowhere to be
    /// reached: no command here needs it to answer.
    var table: CommandTable {
        let support = root.appendingPathComponent("support", isDirectory: true)
        var table = CommandTable()
        table.add(PingCommands.entries(filing: Unfiled(), store: store))
        table.add(NoticeCommands.entries(route: ControlNoticeRoute(support: support)))
        table.add(ControlCommands.entries(support: support, launcher: NoLauncher(), pause: { _ in }))
        table.add(ConfigurationCommands.entries(checks: []))
        return table
    }

    func shipyard(_ arguments: String...) -> CommandResult {
        shipyard(arguments)
    }

    func shipyard(_ arguments: [String]) -> CommandResult {
        ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work", isDirectory: true), variables: [:]),
            now: Self.now
        )
    }

    @Test("an old form runs its new command, with a warning on standard error naming the new form", arguments: [
        (["notify", "--help"], ["notice", "send", "--help"], CommandTable.renamed("notify", "notice send")),
        (["notify", "withdraw", "--help"], ["notice", "withdraw", "--help"], CommandTable.renamed("notify withdraw", "notice withdraw")),
        (["screenshot", "--help"], ["app", "capture", "--help"], CommandTable.renamed("screenshot", "app capture")),
        (["control", "take", "--wait", "x"], ["lease", "take", "--wait", "x"], CommandTable.renamed("control", "lease")),
        (["panel", "tab"], ["panel", "show-tab"], CommandTable.renamed("panel tab", "panel show-tab")),
        (["panel", "view"], ["panel", "show-view"], CommandTable.renamed("panel view", "panel show-view")),
        (["ping", "Ready", "--repo", "owner/shop", "--id", "ready"], ["ping", "send", "Ready", "--repo", "owner/shop", "--id", "ready"],
         CommandTable.renamed("ping <title>", "ping send <title>")),
    ])
    func renamed(old: [String], new: [String], warning: String) {
        defer { try? FileManager.default.removeItem(at: root) }

        let current = shipyard(new)
        let renamed = shipyard(old)

        #expect(renamed == CommandResult(output: current.output, error: warning + current.error, status: current.status))
    }

    @Test("every old name in the table names a command the table runs")
    func renamesLand() {
        let groups = Set(table.entries.map(\.name))
        for rename in CommandTable.renames {
            #expect(groups.contains(rename.new[0]), "\(rename.new) isn't a group")
            #expect(!groups.contains(rename.old[0]) || rename.old.count > 1, "\(rename.old) hides a group")
        }
    }

    @Test("each group's help names every command the table lists for it, and help <group> prints the same")
    func helpMatchesTable() {
        let all = shipyard("--help").output
        for entry in table.entries {
            let help = shipyard(entry.name, "--help")
            #expect(help.status == 0, "\(entry.name)")
            #expect(shipyard("help", entry.name) == help)
            for command in entry.commands {
                let words = (["shipyard", entry.name] + command.usage.split(separator: " ").prefix(1).map(String.init)).joined(separator: " ")
                #expect(help.output.contains(words), "`\(entry.name) --help` doesn't name `\(words)`")
                #expect(all.contains(command.summary), "the top help doesn't summarise `\(words)`")
            }
        }
    }

    @Test("help --json lists every command of the table with its usage and summary, and every old name")
    func helpJSON() throws {
        struct Listing: Decodable {
            struct Command: Decodable { var group: String; var usage: String; var summary: String }
            struct Rename: Decodable { var old: String; var new: String }
            var version: String
            var commands: [Command]
            var renamed: [Rename]
        }

        let result = shipyard("help", "--json")
        let listing = try JSONDecoder().decode(Listing.self, from: Data(result.output.utf8))

        #expect(result.status == 0 && result.error.isEmpty)
        #expect(listing.version == ShipyardVersion.current)
        let table = table
        let summaries = CommandTable.Section.allCases.flatMap { section in
            table.entries.filter { $0.section == section }.flatMap { $0.commands.map(\.summary) }
        }
        #expect(listing.commands.map(\.summary) == summaries)
        #expect(listing.commands.contains { $0.usage == "shipyard ping send <title> [options]" && $0.group == "ping" })
        #expect(listing.renamed.count == CommandTable.renames.count + 1)
    }

    @Test("a mistyped group is one line naming the closest one, exit 2; one far from any just points at the help", arguments: [
        ("pnig", "shipyard: unknown command `pnig`. Did you mean `shipyard ping`? Run `shipyard --help` for the commands.\n"),
        ("noticee", "shipyard: unknown command `noticee`. Did you mean `shipyard notice`? Run `shipyard --help` for the commands.\n"),
        ("deploy", "shipyard: unknown command `deploy`. Run `shipyard --help` for the commands.\n"),
    ])
    func unknown(group: String, line: String) {
        #expect(shipyard(group, "now") == CommandResult(error: line, status: 2))
    }

    @Test("ping list prints the live pings newest first, one line each, and `no pings` when there are none")
    func pingList() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(shipyard("ping", "list") == CommandResult(output: "no pings\n"))

        try store.save(Ping(id: "older", title: "PR ready", projects: ["shop"], sent: Self.now.addingTimeInterval(-7200)))
        try store.save(Ping(id: "newer", title: "Which cache?", projects: [], sent: Self.now.addingTimeInterval(-90), repository: "owner/blog"))
        try store.save(Ping(id: "gone", title: "Expired", projects: [], sent: Self.now.addingTimeInterval(-60), expires: Self.now.addingTimeInterval(-1)))

        #expect(shipyard("ping", "list") == CommandResult(output: "newer  1m  Which cache?  (owner/blog)\nolder  2h  PR ready  (shop)\n"))
    }
}

/// A launcher no test here reaches.
private struct NoLauncher: AppLaunching {
    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {}
}
