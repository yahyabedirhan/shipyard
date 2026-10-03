import Foundation

/// Where app control's socket is: `control.sock` in the app's support
/// folder (`SupportFolder.app`), the user's own (mode 0600), there only
/// while the app runs.
public enum ControlSocket {
    public static let fileName = "control.sock"

    /// The socket the app listens on, in its support folder `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The socket the `shipyard` command asks the running app through,
    /// given the support folder it knows. While `app open --demo` left a
    /// `DemoPointer` there and the demo's socket is there, it's the demo's:
    /// so agents reach a demo run with no variable to repeat. Otherwise
    /// (no demo, or a demo that quit, say from its menu) it's the folder's
    /// own, so a normal app started meanwhile is still found.
    public static func locate(support: URL) -> URL {
        if let demo = DemoPointer.recorded(in: support) {
            let socket = url(in: demo)
            if FileManager.default.fileExists(atPath: socket.path) { return socket }
        }
        return url(in: support)
    }
}

/// The note `shipyard app open --demo` leaves in the normal support
/// folder, naming the demo run's support folder, so the `shipyard` command
/// finds the demo's socket (`ControlSocket.locate`). Plain `app open`
/// removes it. It's the only file a demo run writes outside its folder.
///
/// One JSON file, `demo.json`, private to the `shipyard` command (ADR
/// 0004). It fails safe: a file that's missing, doesn't read, comes from a
/// newer build or names a relative path reads as no demo.
public enum DemoPointer {
    public static let fileName = "demo.json"
    public static let currentVersion = 1

    /// The demo's support folder the pointer in `support` names, if any.
    public static func recorded(in support: URL) -> URL? {
        guard let data = try? Data(contentsOf: url(in: support)),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version <= currentVersion,
              file.support.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: file.support, isDirectory: true)
    }

    /// Points the command at `demo`, the demo run's support folder, from
    /// the normal support folder `support`.
    public static func record(_ demo: URL, in support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(File(version: currentVersion, support: demo.path)).write(to: url(in: support), options: .atomic)
    }

    /// Removes the pointer in `support`; nothing to do when there's none.
    public static func remove(in support: URL) throws {
        let file = url(in: support)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// `demo.json` in `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    // `demo.json`:
    //
    //     { "support": "/Users/me/demo/support", "version": 1 }
    private struct File: Codable {
        var version: Int
        var support: String
    }
}
