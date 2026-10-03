import Foundation

/// Where shipyard keeps what it writes: the one definition of each folder,
/// so the `shipyard` command and the app can't disagree.
public enum SupportFolder {
    /// The variable that moves the app's support folder elsewhere, as
    /// `shipyard app open --demo` launches the app with.
    public static let overrideVariable = "SHIPYARD_SUPPORT_DIR"

    /// The app's folder: `state.json`, `config-status.json`,
    /// `repositories.json`, `config-location.json`, the avatar, the socket
    /// and, on the Mac, the ping store. `SHIPYARD_SUPPORT_DIR` when it's an
    /// absolute path, else `~/Library/Application Support/Shipyard/`.
    public static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        moved(environment: environment)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Shipyard", isDirectory: true)
    }

    /// The folder `SHIPYARD_SUPPORT_DIR` moves the app's to, when it's an
    /// absolute path: what makes a run a demo run.
    public static func moved(environment: [String: String]) -> URL? {
        guard let override = environment[overrideVariable], override.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true)
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
