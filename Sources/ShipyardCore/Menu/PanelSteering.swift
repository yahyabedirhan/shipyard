import ShipyardConfig

/// Why the `shipyard panel` command can't do what it asked: what it named
/// isn't in the menu, or the layout has no tabs. `reason` is the line the
/// command prints, naming what does exist.
public struct PanelRefusal: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

extension ItemKind {
    /// The kinds in the order `shipyard panel show-more` lists them.
    public static let commandOrder: [ItemKind] = [.pullRequest, .issue, .workflowRun, .ping]

    /// The kind as `shipyard panel show-more` names it.
    public var commandName: String {
        switch self {
        case .pullRequest: "pull-requests"
        case .issue: "issues"
        case .workflowRun: "workflow-runs"
        case .ping: "pings"
        }
    }

    /// The kind `name` names, as `commandName` spells it.
    public init?(commandName name: String) {
        guard let kind = Self.commandOrder.first(where: { $0.commandName == name }) else { return nil }
        self = kind
    }
}

// What the `shipyard panel` command names, found in the menu as drawn:
// a project's section, its group of one kind, a tab. Each refusal names
// what exists, so an agent can try again without asking the status.
extension MenuModel {
    /// The section of the project named `project`.
    public func section(named project: String) throws(PanelRefusal) -> MenuSection {
        guard let section = sections.first(where: { $0.name == project }) else {
            let names = sections.map(\.name)
            throw PanelRefusal(names.isEmpty
                ? "no project is named `\(project)`; there are no projects"
                : "no project is named `\(project)`; the projects are \(Self.quoted(names))")
        }
        return section
    }

    /// The group of `project` holding its rows of `kind` (named as
    /// `ItemKind.commandName` spells it). A project grouped by something
    /// else than kind has none.
    public func kindGroup(project: String, kind name: String) throws(PanelRefusal) -> RowGroup {
        guard let kind = ItemKind(commandName: name) else {
            throw PanelRefusal("no kind is named `\(name)`; the kinds are \(Self.quoted(ItemKind.commandOrder.map(\.commandName)))")
        }
        let section = try section(named: project)
        if let group = section.groups.first(where: { $0.id.key == .kind(kind) }) { return group }
        let listed = section.groups.compactMap { group -> String? in
            guard case .kind(let kind) = group.id.key else { return nil }
            return kind.commandName
        }
        throw PanelRefusal(listed.isEmpty
            ? "`\(project)` lists no group by kind; show-more needs `group-by = \"kind\"`, the default"
            : "`\(project)` lists no \(name); its kinds are \(Self.quoted(listed))")
    }

    /// The tab `name` names: a project's, or `All` (in any case) unless a
    /// project has that name. Refused in the list layout, which has no tabs.
    public func tab(named name: String) throws(PanelRefusal) -> MenuTab {
        guard layout == .tabs else {
            throw PanelRefusal("the menu uses the list layout; tabs need `[menu] layout = \"tabs\"`")
        }
        if sections.contains(where: { $0.name == name }) { return .project(name) }
        if name.lowercased() == "all" { return .all }
        throw PanelRefusal("no tab is named `\(name)`; the tabs are \(Self.quoted(tabs.map(PanelText.tabTitle)))")
    }

    /// Every section's name, in menu order, as `fold`, `unfold` and `tab`
    /// accept them: the projects', then the remote machines'.
    public var projectNames: [String] {
        sections.map(\.name)
    }

    /// The projects whose sections are collapsed, in menu order.
    public var collapsedProjects: [String] {
        sections.filter(\.isCollapsed).map(\.name)
    }

    /// The groups by kind that Show more opened, in menu order.
    public var kindGroupsShowingAll: [(project: String, kind: ItemKind)] {
        sections.flatMap { section in
            section.groups.compactMap { group in
                guard group.isExpanded, case .kind(let kind) = group.id.key else { return nil }
                return (section.name, kind)
            }
        }
    }

    private static func quoted(_ names: [String]) -> String {
        names.map { "`\($0)`" }.joined(separator: ", ")
    }
}

// The orchestrator's operations behind `shipyard panel fold`, `unfold` and
// `show-more`: the same ones a click runs, reached by name.
extension Shipyard {
    /// Collapses (`collapsed` true) or expands the section of the project
    /// named `project`, through `toggleCollapsed`, only when it differs.
    public func setCollapsed(_ project: String, _ collapsed: Bool) throws(PanelRefusal) {
        let section = try menu.section(named: project)
        guard section.isCollapsed != collapsed else { return }
        toggleCollapsed(project)
    }

    /// Shows every row of `project`'s group of `kind`, through
    /// `showMore(_:)`; a group that isn't capped stays as it is.
    public func showMore(_ project: String, kind: String) throws(PanelRefusal) {
        let group = try menu.kindGroup(project: project, kind: kind)
        showMore(group.id)
    }
}
