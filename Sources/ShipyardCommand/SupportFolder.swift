import Foundation

/// Where shipyard keeps what it writes: the one definition of each folder,
/// so the `shipyard` command and the app can't disagree.
public enum SupportFolder {
    /// `~/Library/Application Support/Shipyard/`, the app's: `state.json`,
    /// `repositories.json`, the avatar and, on the Mac, the ping store.
    public static var app: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shipyard", isDirectory: true)
    }

    /// The folder the `shipyard` command keeps its data in on a machine
    /// without the app: `$XDG_DATA_HOME/shipyard`, or
    /// `~/.local/share/shipyard` when `XDG_DATA_HOME` is unset, empty or
    /// not an absolute path.
    public static func withoutTheApp(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base: URL
        if let xdg = environment["XDG_DATA_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".local/share", isDirectory: true)
        }
        return base.appendingPathComponent("shipyard", isDirectory: true)
    }
}
