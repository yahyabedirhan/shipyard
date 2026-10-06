import Foundation
import ShipyardConfig

/// One banner the panel shows above the projects, about a condition that
/// holds now: its key, which names the condition (never its words), what
/// kind it is (the panel picks its symbol and tint by it) and its words.
/// The lease's banners aren't these: the app draws them from the lease.
public struct PanelBanner: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// The configuration file was rejected: never dismissable.
        case configError
        /// Settings the file has but shipyard ignores, or old forms it read.
        case configWarnings
        /// Refreshing slower than configured (stretched or backed off).
        case delay
        /// Refreshing paused until a rate limit resets.
        case paused
        /// The latest refresh failed; the rows are kept.
        case fetch
        /// A remote machine's quiet line (`MachineNotice`).
        case machine
        /// macOS doesn't let shipyard post notifications.
        case notificationsOff
    }

    /// The banner key: `config`, `config-warnings`, `delay`, `paused`,
    /// `fetch`, `machine-<machine>` or `notifications`. A snooze is kept
    /// by it, so words that change (2 min, then 4 min) keep the banner hidden.
    public var id: String
    public var kind: Kind
    public var text: String

    public init(id: String, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// Whether the user can dismiss it for an hour: every banner but the
    /// configuration error's, which says the file is being ignored.
    public var isDismissable: Bool { kind != .configError }

    /// Every banner whose condition holds, in the panel's order: the
    /// configuration error, its warnings, then once `ready` the refresh
    /// delay (or pause), the fetch error and one quiet line per remote
    /// machine; then notifications off, which the app knows
    /// (`notificationsOff`). `sharePercent` is `[rate-limit]
    /// max-share-percent`, for the delay's words.
    public static func list(
        configError: ConfigError?,
        configWarnings: [ConfigIssue],
        ready: Bool,
        menu: MenuModel,
        sharePercent: Int,
        notificationsOff: Bool
    ) -> [PanelBanner] {
        var banners: [PanelBanner] = []
        if let configError {
            banners.append(PanelBanner(id: "config", kind: .configError, text: PanelText.configError(configError)))
        }
        if let text = PanelText.configWarnings(configWarnings) {
            banners.append(PanelBanner(id: "config-warnings", kind: .configWarnings, text: text))
        }
        if ready {
            if let text = PanelText.refreshDelay(menu.refreshDelay, sharePercent: sharePercent) {
                banners.append(menu.canRefreshNow
                    ? PanelBanner(id: "delay", kind: .delay, text: text)
                    : PanelBanner(id: "paused", kind: .paused, text: text))
            }
            if let error = menu.bannerFetchError {
                banners.append(PanelBanner(id: "fetch", kind: .fetch, text: PanelText.fetchError(error)))
            }
            for notice in menu.machineNotices {
                banners.append(PanelBanner(id: "machine-\(notice.id)", kind: .machine, text: PanelText.machineNotice(notice)))
            }
        }
        if notificationsOff {
            banners.append(PanelBanner(id: "notifications", kind: .notificationsOff, text: PanelText.notificationsOff))
        }
        return banners
    }
}
