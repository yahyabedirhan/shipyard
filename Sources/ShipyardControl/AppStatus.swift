import Foundation

/// What `shipyard app status` reports about the running app: its version,
/// whether the panel is open, the menu's layout and the selected tab, the
/// projects in the configuration's order, which of them are folded and
/// which groups Show more opened. The app fills it; how it reads, as lines
/// or as `--json`, is decided here, so the format is one contract.
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

    public init(
        version: String,
        panelOpen: Bool,
        layout: String,
        tab: String? = nil,
        projects: [String],
        folded: [String] = [],
        showingAll: [Group] = []
    ) {
        self.version = version
        self.panelOpen = panelOpen
        self.layout = layout
        self.tab = tab
        self.projects = projects
        self.folded = folded
        self.showingAll = showingAll
    }

    /// The status as lines, for a person; `tab` only in the tabs layout:
    ///
    ///     shipyard 0.1.0 is running
    ///     panel: closed
    ///     layout: tabs
    ///     tab: All
    ///     projects: shop, blog
    ///     folded: none
    ///     showing all: pull-requests in shop
    public var text: String {
        var lines = [
            "shipyard \(version) is running",
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

    /// The status as one JSON object on one line, keys sorted; `tab` is
    /// `null` in the list layout, never left out.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self) + "\n"
    }

    private enum CodingKeys: String, CodingKey {
        case running, version, panelOpen, layout, tab, projects, folded, showingAll
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
    }
}
