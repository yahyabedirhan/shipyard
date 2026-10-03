import Foundation
import ShipyardCommand
import ShipyardNotices
import Testing

/// `shipyard notify` on a machine that leaves its notices with the
/// herdr-shipyard plugin for the Mac's poll (`PluginNoticeRoute`), through
/// `ShipyardCLI.run`: a home folder with the plugin linked at
/// `~/.local/bin/shipyard` as its install does, and a stand-in for the
/// plugin's `scripts/notices.sh` that records what it's handed and exits
/// as the real one does. Whether the Mac shows a queued notice is the
/// Mac's to say (`RemoteNoticeTests`).
@Suite("The notify command on the poll route")
struct QueuedNoticeCommandTests {
    static let sent = Date(timeIntervalSince1970: 1_790_966_400)

    /// A home folder with the plugin at `plugin/`, linked unless `linked`
    /// is false, its `scripts/notices.sh` running `script` unless it's `nil`.
    struct Home {
        let root: URL
        var plugin: URL { root.appendingPathComponent("plugins/herdr-shipyard", isDirectory: true) }
        /// What the script was run with, one argument per line.
        var arguments: String? { try? String(contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8) }
        /// What the script read on standard input.
        var input: Data? { try? Data(contentsOf: root.appendingPathComponent("input")) }

        init(script: String? = Home.storing, linkTo target: String? = nil, linked: Bool = true) throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("n195-home-\(UUID().uuidString)", isDirectory: true)
            let files = FileManager.default
            try files.createDirectory(at: plugin.appendingPathComponent("bin"), withIntermediateDirectories: true)
            files.createFile(atPath: plugin.appendingPathComponent("bin/shipyard").path, contents: Data())
            if let script {
                try files.createDirectory(at: plugin.appendingPathComponent("scripts"), withIntermediateDirectories: true)
                try script.replacingOccurrences(of: "$RECORD", with: root.path)
                    .write(to: plugin.appendingPathComponent("scripts/notices.sh"), atomically: true, encoding: .utf8)
            }
            if linked {
                let bin = root.appendingPathComponent(".local/bin", isDirectory: true)
                try files.createDirectory(at: bin, withIntermediateDirectories: true)
                try files.createSymbolicLink(
                    atPath: bin.appendingPathComponent("shipyard").path,
                    withDestinationPath: target ?? plugin.appendingPathComponent("bin/shipyard").path
                )
            }
        }

        /// Stores the notice: records its arguments and input, exits 0.
        static let storing = """
            printf '%s\\n' "$@" > "$RECORD/arguments"
            cat > "$RECORD/input"
            """

        /// Refuses a notice too large for a listing, in the plugin's words.
        static let tooLarge = """
            cat > /dev/null
            echo "herdr-shipyard: the notice is 50000 bytes, more than a listing can carry (49108 bytes)" >&2
            exit 1
            """

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Runs `shipyard <arguments>` with the poll route over `home`.
    func shipyard(_ arguments: [String], home: Home) -> CommandResult {
        var table = CommandTable()
        table.add(NoticeCommands.entries(route: PluginNoticeRoute(home: home.root, now: { Self.sent })))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(
                workingDirectory: URL(fileURLWithPath: "/work/shop", isDirectory: true),
                variables: [:],
                git: NoOrigin()
            ),
            now: Self.sent
        )
    }

    struct NoOrigin: GitRemoteLookup {
        func origin(in folder: URL) -> String? { nil }
    }

    @Test("the notice goes to the plugin's notices.sh add <id>, as its JSON with the id and when it was sent, and the command says it's queued")
    func queued() throws {
        let home = try Home()
        defer { home.remove() }

        let result = shipyard(["notify", "Tests running", "--body", "12 of 40 passed", "--from", "claude", "--repo", "owner/shop"], home: home)

        #expect(result == CommandResult(output: "queued; shown within about 30 seconds if the Mac is awake\n"))
        let arguments = try #require(home.arguments).split(separator: "\n").map(String.init)
        #expect(arguments.count == 2)
        #expect(arguments.first == "add")
        let stored = try #require(home.input)
        // The notice's own JSON as is, under the id it's stored by and when
        // it was sent; compact, one line, `sent` in ISO 8601: what the Mac reads back.
        #expect(!arguments[1].isEmpty)
        #expect(String(decoding: stored, as: UTF8.self) == #"{"id":"\#(arguments[1])","notice":{"body":"12 of 40 passed","from":"claude","repository":"owner/shop","title":"Tests running"},"sent":"2026-10-02T18:40:00Z"}"#)
    }

    @Test("each notice is queued under an id of its own")
    func idsDiffer() throws {
        let home = try Home()
        defer { home.remove() }
        _ = shipyard(["notify", "One", "--project", "shop"], home: home)
        let first = try #require(home.arguments)
        _ = shipyard(["notify", "Two", "--project", "shop"], home: home)
        #expect(try #require(home.arguments) != first)
    }

    @Test("the plugin refusing the notice exits 1 with its reason, without the plugin's prefix")
    func refused() throws {
        let home = try Home(script: Home.tooLarge)
        defer { home.remove() }

        let result = shipyard(["notify", "Done", "--project", "shop"], home: home)

        #expect(result == .failed("shipyard notify: the herdr-shipyard plugin didn't queue this notice: the notice is 50000 bytes, more than a listing can carry (49108 bytes)"))
    }

    @Test("a plugin failing without a word exits 1 with its status")
    func failedSilently() throws {
        let home = try Home(script: "exit 3")
        defer { home.remove() }
        #expect(shipyard(["notify", "Done", "--project", "shop"], home: home)
            == .failed("shipyard notify: the herdr-shipyard plugin didn't queue this notice (exit 3)"))
    }

    @Test("without the plugin's link, or with a link elsewhere, it exits 1 saying to install the plugin")
    func pluginMissing() throws {
        let unlinked = try Home(linked: false)
        defer { unlinked.remove() }
        let link = unlinked.root.appendingPathComponent(".local/bin/shipyard").path
        #expect(shipyard(["notify", "Done", "--project", "shop"], home: unlinked)
            == .failed("shipyard notify: \(link) isn't the herdr-shipyard plugin's link, so this notice can't wait for the Mac; install the plugin (herdr plugin install yahyabedirhan/herdr-shipyard)"))

        let elsewhere = try Home(linkTo: "/usr/local/lib/shipyard")
        defer { elsewhere.remove() }
        let other = elsewhere.root.appendingPathComponent(".local/bin/shipyard").path
        #expect(shipyard(["notify", "Done", "--project", "shop"], home: elsewhere)
            == .failed("shipyard notify: \(other) links to /usr/local/lib/shipyard, not a herdr-shipyard plugin's shipyard, so this notice can't wait for the Mac; install the plugin (herdr plugin install yahyabedirhan/herdr-shipyard)"))
    }

    @Test("a plugin too old to hold notices exits 1 saying to update it")
    func pluginTooOld() throws {
        let home = try Home(script: nil)
        defer { home.remove() }
        #expect(shipyard(["notify", "Done", "--project", "shop"], home: home)
            == .failed("shipyard notify: the herdr-shipyard plugin at \(home.plugin.path) can't hold notices; update it (herdr plugin install yahyabedirhan/herdr-shipyard)"))
    }

    @Test("arguments that don't read exit 2 before the plugin is asked")
    func usage() throws {
        let home = try Home()
        defer { home.remove() }
        #expect(shipyard(["notify"], home: home).status == CommandResult.usageStatus)
        #expect(home.arguments == nil)
    }
}
