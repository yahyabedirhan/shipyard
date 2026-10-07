import Foundation
import ShipyardConfig

/// One banner the panel shows above the projects, about a condition that
/// holds now: its key, which names the condition (never its words), what
/// kind it is (the panel picks its symbol and tint by it) and its words.
/// Every banner can be dismissed for an hour (`BannerSnoozes`).
public struct PanelBanner: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// An agent holds app control's lease: the app draws it from the
        /// lease, with its countdown and Stop.
        case lease
        /// A holder the maintainer stopped is still barred: its quiet line,
        /// whose Allow lets the holder (by its key) back.
        case stoppedHolder(key: String)
        /// The configuration file was rejected.
        case configError
        /// Settings the file has but shipyard ignores, or old forms it read.
        case configWarnings
        /// Refreshing slower than configured because a rate limit is low
        /// (backed off); an interval only stretched to stay within the
        /// rate-limit share has no banner.
        case delay
        /// Refreshing paused until a rate limit resets.
        case paused
        /// The latest refresh failed; the rows are kept.
        case fetch
        /// A remote machine's quiet line (`MachineNotice`).
        case machine
        /// Notes can't be listed: no ntn, ntn logged out, or ntn's workspace has
        /// no Shipyard Notes page.
        case notes
        /// macOS doesn't let shipyard post notifications.
        case notificationsOff
    }

    /// The banner key: `lease`, `stopped-<holder key>`, `config`,
    /// `config-warnings`, `delay`, `paused`, `fetch`, `machine-<machine>`,
    /// `notes` or `notifications`. A snooze is kept by it, so words that change
    /// (2 min, then 4 min) keep the banner hidden.
    public var id: String
    public var kind: Kind
    public var text: String

    public init(id: String, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// App control's lease as its banners show it, which only the app knows:
    /// the lease held now and the holders the maintainer stopped.
    public struct Lease: Equatable, Sendable {
        /// The lease held now; nil while it's free.
        public var held: Held?
        /// Each holder the maintainer stopped that's still barred, the latest first.
        public var stopped: [Stopped]

        public init(held: Held? = nil, stopped: [Stopped] = []) {
            self.held = held
            self.stopped = stopped
        }

        /// A lease held: `term` tells one lease from the next (its holder
        /// and when it was taken, the same through renewals); `headline` is
        /// the banner's first line.
        public struct Held: Equatable, Sendable {
            public var term: String
            public var headline: String

            public init(term: String, headline: String) {
                self.term = term
                self.headline = headline
            }
        }

        /// A stopped holder: its key, and its quiet line's words.
        public struct Stopped: Equatable, Sendable {
            public var key: String
            public var text: String

            public init(key: String, text: String) {
                self.key = key
                self.text = text
            }
        }
    }

    /// Every banner whose condition holds, in the panel's order: the
    /// lease's banner and each stopped holder's quiet line, in every phase;
    /// then the configuration error, its warnings, then once `ready` the refresh
    /// delay (or pause), the fetch error and one quiet line per remote
    /// machine, and the notes banner; then notifications off, which the app knows
    /// (`notificationsOff`).
    public static func list(
        lease: Lease = Lease(),
        configError: ConfigError?,
        configWarnings: [ConfigIssue],
        ready: Bool,
        menu: MenuModel,
        notes: NotesNotice? = nil,
        notificationsOff: Bool
    ) -> [PanelBanner] {
        var banners: [PanelBanner] = []
        if let held = lease.held {
            banners.append(PanelBanner(id: "lease", kind: .lease, text: held.headline))
        }
        for holder in lease.stopped {
            banners.append(PanelBanner(id: "stopped-\(holder.key)", kind: .stoppedHolder(key: holder.key), text: holder.text))
        }
        if let configError {
            banners.append(PanelBanner(id: "config", kind: .configError, text: PanelText.configError(configError)))
        }
        if let text = PanelText.configWarnings(configWarnings) {
            banners.append(PanelBanner(id: "config-warnings", kind: .configWarnings, text: text))
        }
        if ready {
            if let text = PanelText.refreshDelay(menu.refreshDelay) {
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
            if let notes {
                banners.append(PanelBanner(id: "notes", kind: .notes, text: PanelText.notesNotice(notes)))
            }
        }
        if notificationsOff {
            banners.append(PanelBanner(id: "notifications", kind: .notificationsOff, text: PanelText.notificationsOff))
        }
        return banners
    }
}
