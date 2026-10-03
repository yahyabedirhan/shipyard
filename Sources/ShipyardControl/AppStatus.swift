import Foundation

/// What `shipyard app status` reports about the running app: its version,
/// whether the panel is open, the menu's layout and the projects, in the
/// configuration's order. The app fills it; how it reads, as lines or as
/// `--json`, is decided here, so the format is one contract.
public struct AppStatus: Codable, Equatable, Sendable {
    /// Always true: a status only comes from a running app. It's in the
    /// JSON so an agent reads one field, not the exit status alone.
    public var running = true
    public var version: String
    public var panelOpen: Bool
    /// `list` or `tabs`, as `[menu] layout` spells it.
    public var layout: String
    public var projects: [String]

    public init(version: String, panelOpen: Bool, layout: String, projects: [String]) {
        self.version = version
        self.panelOpen = panelOpen
        self.layout = layout
        self.projects = projects
    }

    /// The status as lines, for a person:
    ///
    ///     shipyard 0.1.0 is running
    ///     panel: closed
    ///     layout: tabs
    ///     projects: shop, blog
    public var text: String {
        """
        shipyard \(version) is running
        panel: \(panelOpen ? "open" : "closed")
        layout: \(layout)
        projects: \(projects.isEmpty ? "none" : projects.joined(separator: ", "))

        """
    }

    /// The status as one JSON object on one line, keys sorted.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self) + "\n"
    }
}
