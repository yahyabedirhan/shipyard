import Foundation
import ShipyardCommand

/// The slow way for a notice to reach the Mac from another machine: the
/// herdr-shipyard plugin holds it until the Mac's poll of the machine
/// collects it, through the same Herdr connection remote pings take (ADR
/// 0005). The notice is queued, not shown: the Mac shows it by the user's
/// rules when it arrives, within about 30 seconds while it's awake, and
/// drops it when it arrives more than ten minutes late.
///
/// The plugin's `shipyard` is linked at `~/.local/bin/shipyard`; the
/// plugin's folder is that link's target less `bin/shipyard`, and its
/// `scripts/notices.sh add <id>` stores the notice (`QueuedNotice`) given
/// on standard input: exit 0 stored, 1 too large, 2 misused. A notice is
/// stored under its `--id` when it has one, so a replace sent before the
/// Mac's poll overwrites the one waiting, and `notices.sh remove <id>`
/// takes a waiting one away for `shipyard notify withdraw <id>`. A notice's
/// image isn't carried on this route: the plugin's listing is too small
/// for one, so it's dropped before the notice is stored.
public struct PluginNoticeRoute: NoticeRoute {
    private let home: URL
    private let now: @Sendable () -> Date

    /// What the agent reads once the notice is queued.
    public static let queuedLine = "queued; shown within about 30 seconds if the Mac is awake"

    /// What the agent reads once a withdrawal took the notice out of the
    /// queue: one the Mac already collected isn't reached from here.
    public static let withdrawnLine = "withdrawn if it was still waiting; one the Mac already showed stays"

    /// The plugin's link, under the home folder.
    static let linkPath = ".local/bin/shipyard"
    /// The plugin's `shipyard`, under its folder.
    static let binarySuffix = "/bin/shipyard"
    /// The script that holds notices, under the plugin's folder.
    static let scriptPath = "scripts/notices.sh"

    private static let install = "herdr plugin install yahyabedirhan/herdr-shipyard"

    /// Finds the plugin through `home`'s `~/.local/bin/shipyard`; `now` dates the notice.
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.home = home
        self.now = now
    }

    public func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict {
        let script: URL
        switch locateScript() {
        case .success(let found): script = found
        case .failure(let refusal): return .refused(refusal.message)
        }
        let arguments: [String], input: Data, failing: String
        switch request {
        case .show(var notice):
            notice.image = nil
            let queued = QueuedNotice(id: notice.id ?? UUID().uuidString.lowercased(), sent: now(), notice: notice)
            (arguments, input, failing) = (["add", queued.id], queued.encoded(), "queue this notice")
        case .withdraw(let id):
            (arguments, input, failing) = (["remove", id], Data(), "withdraw the notice")
        }
        guard let ran = Self.run(script: script, arguments: arguments, input: input) else {
            return .refused("couldn't run the herdr-shipyard plugin's \(script.path), so it didn't \(failing)")
        }
        switch ran.status {
        case 0:
            return .queued
        default:
            let said = Self.lastLine(ran.error).map { ": \($0)" } ?? " (exit \(ran.status))"
            return .refused("the herdr-shipyard plugin didn't \(failing)\(said)")
        }
    }

    /// Why the notice can't be queued, as the agent reads it.
    struct Refusal: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    /// The plugin's `scripts/notices.sh`, or why it isn't there.
    func locateScript() -> Result<URL, Refusal> {
        let link = home.appendingPathComponent(Self.linkPath, isDirectory: false)
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return .failure(Refusal("\(link.path) isn't the herdr-shipyard plugin's link, so this notice can't wait for the Mac; install the plugin (\(Self.install))"))
        }
        // The plugin links it by its absolute path; a relative one is from the link's folder.
        let binary = target.hasPrefix("/") ? target : link.deletingLastPathComponent().appendingPathComponent(target).path
        guard binary.hasSuffix(Self.binarySuffix) else {
            return .failure(Refusal("\(link.path) links to \(binary), not a herdr-shipyard plugin's shipyard, so this notice can't wait for the Mac; install the plugin (\(Self.install))"))
        }
        let plugin = URL(fileURLWithPath: String(binary.dropLast(Self.binarySuffix.count)), isDirectory: true)
        let script = plugin.appendingPathComponent(Self.scriptPath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .failure(Refusal("the herdr-shipyard plugin at \(plugin.path) can't hold notices; update it (\(Self.install))"))
        }
        return .success(script)
    }

    /// What a script run said on standard error, and its status.
    struct ScriptOutput {
        var status: Int32
        var error: String
    }

    /// Runs `sh <script> <arguments>` with `input` on standard input,
    /// standard output dropped; `nil` when it couldn't start. The input
    /// goes through a temporary file, not a pipe, so a script that exits
    /// without reading it can't break the write.
    static func run(script: URL, arguments: [String], input: Data) -> ScriptOutput? {
        let inputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-notice-\(UUID().uuidString).json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: inputFile) }
        guard FileManager.default.createFile(atPath: inputFile.path, contents: input),
              let reading = FileHandle(forReadingAtPath: inputFile.path)
        else { return nil }
        defer { try? reading.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + arguments
        process.standardInput = reading
        process.standardOutput = FileHandle.nullDevice
        let error = Pipe()
        process.standardError = error
        do {
            try process.run()
        } catch {
            return nil
        }
        let said = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptOutput(status: process.terminationStatus, error: String(decoding: said, as: UTF8.self))
    }

    /// The last line `text` holds, without the plugin's `herdr-shipyard: `.
    static func lastLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let plain = line.hasPrefix("herdr-shipyard: ") ? String(line.dropFirst("herdr-shipyard: ".count)) : line
        return plain.isEmpty ? nil : plain
    }
}
