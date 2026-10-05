import Foundation

/// What `shipyard app status` reports about the running app: its version,
/// the demo folder in a demo run, whether the panel is open, the menu's
/// layout and the selected tab, the projects in the configuration's order,
/// which of them are folded, which groups Show more opened, and the lease. The app
/// fills it; how it reads, as lines or as `--json`, is decided here, so the
/// format is one contract.
public struct AppStatus: Codable, Equatable, Sendable {
    /// A group Show more opened: its project, and its kind as `shipyard
    /// panel show-more` names it (`pull-requests`).
    public struct Group: Codable, Equatable, Sendable {
        public var project: String
        public var kind: String

        public init(project: String, kind: String) {
            self.project = project
            self.kind = kind
        }
    }

    /// The lease (`ControlLease`) as `app status` reports it: who holds
    /// app control, where they run, how long is left and how many wait.
    public struct Lease: Codable, Equatable, Sendable {
        /// The holder's name (`Claude Code`).
        public var holder: String
        /// Where the holder runs: `Herdr pane <id>`, or its working folder.
        public var place: String
        public var secondsLeft: Int
        public var waiting: Int
        /// Why the holder took shipyard (`control take --for`); left out of
        /// the JSON when it didn't say.
        public var purpose: String?
        /// What the holder is doing ("Taking a screenshot…"), or last did
        /// and when ("Took a screenshot · 12s ago"); left out of the JSON
        /// before its first step.
        public var step: String?

        public init(holder: String, place: String, secondsLeft: Int, waiting: Int, purpose: String? = nil, step: String? = nil) {
            self.holder = holder
            self.place = place
            self.secondsLeft = secondsLeft
            self.waiting = waiting
            self.purpose = purpose
            self.step = step
        }
    }

    /// Always true: a status only comes from a running app. It's in the
    /// JSON so an agent reads one field, not the exit status alone.
    public var running = true
    public var version: String
    public var panelOpen: Bool
    /// `list` or `tabs`, as `[menu] layout` spells it.
    public var layout: String
    /// The tabs layout's selected tab: a project's name, or `All`; `nil`
    /// (`null` in the JSON) in the list layout.
    public var tab: String?
    public var projects: [String]
    /// The projects whose sections are folded (collapsed), in menu order.
    public var folded: [String]
    /// The groups showing every row past their cap, in menu order.
    public var showingAll: [Group]
    /// The folder a demo run (`app open --demo`) reads, or nil for the
    /// user's own app (`null` in the JSON, never left out).
    public var demo: String?
    /// The lease, or nil when it's free (`null` in the JSON, never left
    /// out). The app's control server fills it.
    public var lease: Lease?

    public init(
        version: String,
        panelOpen: Bool,
        layout: String,
        tab: String? = nil,
        projects: [String],
        folded: [String] = [],
        showingAll: [Group] = [],
        demo: String? = nil,
        lease: Lease? = nil
    ) {
        self.version = version
        self.panelOpen = panelOpen
        self.layout = layout
        self.tab = tab
        self.projects = projects
        self.folded = folded
        self.showingAll = showingAll
        self.demo = demo
        self.lease = lease
    }

    /// The status as lines, for a person; `demo` only in a demo run, `tab`
    /// only in the tabs layout:
    ///
    ///     shipyard 0.2.0 is running
    ///     demo: /Users/me/demo
    ///     lease: Claude Code in /Users/me/shop, 48s left, 0 waiting
    ///     panel: closed
    ///     layout: tabs
    ///     tab: All
    ///     projects: shop, blog
    ///     folded: none
    ///     showing all: pull-requests in shop
    public var text: String {
        var lines = ["shipyard \(version) is running"]
        if let demo { lines.append("demo: \(demo)") }
        if let lease {
            lines.append("lease: \(lease.holder) in \(lease.place), \(lease.secondsLeft)s left, \(lease.waiting) waiting")
        } else {
            lines.append("lease: free")
        }
        lines += [
            "panel: \(panelOpen ? "open" : "closed")",
            "layout: \(layout)",
        ]
        if let tab { lines.append("tab: \(tab)") }
        lines += [
            "projects: \(Self.list(projects))",
            "folded: \(Self.list(folded))",
            "showing all: \(Self.list(showingAll.map { "\($0.kind) in \($0.project)" }))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    /// The status as one JSON object on one line, keys sorted; `tab`,
    /// `demo` and `lease` are `null` when there's none, never left out.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self) + "\n"
    }

    private enum CodingKeys: String, CodingKey {
        case running, version, panelOpen, layout, tab, projects, folded, showingAll, demo, lease
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(running, forKey: .running)
        try container.encode(version, forKey: .version)
        try container.encode(panelOpen, forKey: .panelOpen)
        try container.encode(layout, forKey: .layout)
        try container.encode(tab, forKey: .tab)
        try container.encode(projects, forKey: .projects)
        try container.encode(folded, forKey: .folded)
        try container.encode(showingAll, forKey: .showingAll)
        try container.encode(demo, forKey: .demo)
        try container.encode(lease, forKey: .lease)
    }
}
