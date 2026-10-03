import Foundation
import ShipyardCommand
import ShipyardConfig
import ShipyardPings

/// Where the app reads and writes, decided once from the environment it was
/// launched with: `config.toml` (`XDG_CONFIG_HOME`), and the support folder
/// (`SHIPYARD_SUPPORT_DIR`) that holds everything else it keeps. The app
/// builds every store on these paths, so a demo run
/// (`shipyard app open --demo`, which sets both) reads and writes only in
/// its folder, and leaves the user's login item alone.
public struct AppFiles: Equatable, Sendable {
    /// The configuration file.
    public var config: URL
    /// The support folder: `state.json`, `config-status.json`,
    /// `repositories.json`, `config-location.json`, `Pings/`, `Avatar/` and
    /// the control socket.
    public var support: URL
    /// The folder a demo run reads, for `app status`: nil unless the app
    /// was launched with `SHIPYARD_SUPPORT_DIR`; then the
    /// `XDG_CONFIG_HOME` it was launched with (the folder
    /// `app open --demo` names), else the support folder itself.
    public var demo: URL?

    public init(config: URL, support: URL, demo: URL? = nil) {
        self.config = config
        self.support = support
        self.demo = demo
    }

    /// The paths the app uses when launched with `environment`; `home`
    /// is where `config.toml` is looked up without `XDG_CONFIG_HOME`.
    public init(
        environment: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        config = ConfigStore.defaultURL(environment: environment, home: home)
        support = SupportFolder.app(environment: environment)
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
        demo = SupportFolder.moved(environment: environment).map { configHome ?? $0 }
    }

    /// The ping store's folder, `Pings/` in the support folder.
    public var pings: URL { PingStore.appDirectory(in: support) }
    /// The avatar cache's folder, `Avatar/` in the support folder.
    public var avatars: URL { support.appendingPathComponent("Avatar", isDirectory: true) }

    /// The login item the app follows `launch-at-login` with: `item`, or in
    /// a demo run one that changes nothing, since the login item is the
    /// user's app's (one bundle), not the demo folder's.
    public func loginItem(_ item: any LoginItem) -> any LoginItem {
        demo == nil ? item : LeftAlone()
    }

    /// A login item a demo run leaves as the user set it.
    private struct LeftAlone: LoginItem {
        func setEnabled(_ enabled: Bool) {}
    }
}
