import Foundation
import ShipyardCommand
import ShipyardControl
import ShipyardNotices
@testable import ShipyardPings
import Testing

/// The `shipyard` router as the Mac's build assembles it: every group its
/// `main.swift` adds, run through `ShipyardCLI.run`. The contract it owns is
/// the command table's: the help is made from it, `help --json` lists it,
/// a form from before the noun-verb tree is refused, and a mistyped group
/// gets the closest one. Each group's own behaviour is its own suite's.
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

    @Test("a form from before the noun-verb tree is refused in one line, exit 2, and runs nothing", arguments: [
        (["ping", "Ready", "--repo", "owner/shop"],
         "shipyard ping: unknown command `Ready`; send a ping with `shipyard ping send <title>`. Run `shipyard ping --help` for usage.\n"),
        (["notify", "Done"], "shipyard: unknown command `notify`. Did you mean `shipyard notice`? Run `shipyard --help` for the commands.\n"),
        (["screenshot", "x.png"], "shipyard: unknown command `screenshot`. Run `shipyard --help` for the commands.\n"),
        (["control", "take"], "shipyard: unknown command `control`. Run `shipyard --help` for the commands.\n"),
        (["panel", "tab", "shop"], "shipyard panel: unknown command `tab`. Run `shipyard panel --help` for usage.\n"),
        (["panel", "view", "cli"], "shipyard panel: unknown command `view`. Run `shipyard panel --help` for usage.\n"),
    ])
    func oldForm(arguments: [String], line: String) {
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(shipyard(arguments) == CommandResult(error: line, status: 2))
        #expect(store.all().isEmpty)
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

    @Test("help --json lists every command of the table with its usage and summary")
    func helpJSON() throws {
        struct Listing: Decodable {
            struct Command: Decodable { var group: String; var usage: String; var summary: String }
            var version: String
            var commands: [Command]
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
