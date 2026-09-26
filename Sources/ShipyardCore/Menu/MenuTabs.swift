import Foundation

/// One tab of the tabs layout: every project, or one of them by name.
public enum MenuTab: Hashable, Sendable {
    case all
    case project(String)
}

/// What a tab of the tabs layout lists: its rows in groups, its projects'
/// error rows, and what the line under the tab strip counts.
public struct MenuTabContent: Equatable, Sendable {
    /// A project's groups as its arrangement makes them, the same as in
    /// the list; All's by kind (pull requests, then issues, then runs) under
    /// subheaders, newest first. A group with no rows is left out.
    public var groups: [RowGroup]
    /// One per repository of the tab's projects that couldn't be fetched.
    public var errors: [MenuErrorRow]
    /// Its projects' notes, such as the review search's limit.
    public var notes: [String]
    /// Rows in the tab needing attention.
    public var attentionCount: Int
    /// How many projects the tab holds: all of them, or one.
    public var projectCount: Int
    /// Whether a row's second line names its repository.
    public var showsRepository: Bool
    /// Whether every one of its projects' rows was fetched: `false` before
    /// the first refresh succeeded, or for a project added since.
    public var isLoaded: Bool
}

extension MenuModel {
    /// The All tab's fixed arrangement, whatever the projects set: by kind,
    /// newest first, with the tabs' kind subheaders.
    static let allTabArrangement = ArrangementSettings(groupBy: .kind, subsections: true, sortBy: .updated)

    /// All, then one tab per project in configuration order.
    public var tabs: [MenuTab] {
        [.all] + sections.map { .project($0.name) }
    }

    /// The tab's attention count: its project's, or for All the attention
    /// count (a row listed in two projects counts once); 0 for a project
    /// that isn't there.
    public func attentionCount(for tab: MenuTab) -> Int {
        switch tab {
        case .all: attention.total
        case .project(let name): sections.first { $0.name == name }?.attentionCount ?? 0
        }
    }

    /// The tab `step` places from `tab` in the strip (← is -1, → is 1),
    /// wrapping from the last tab to All and back. A tab whose
    /// project is gone counts as All.
    public func tab(beside tab: MenuTab, by step: Int) -> MenuTab {
        let tabs = tabs
        let index = tabs.firstIndex(of: resolved(tab)) ?? 0
        let count = tabs.count
        return tabs[((index + step) % count + count) % count]
    }

    /// `tab`, or All once its project was removed from the configuration.
    public func resolved(_ tab: MenuTab) -> MenuTab {
        switch tab {
        case .all: .all
        case .project(let name): sections.contains { $0.name == name } ? tab : .all
        }
    }

    /// What `tab` lists. A project's tab lists its section's groups. All
    /// takes every project's rows, a row listed in two projects once, in
    /// its fixed arrangement (by kind, newest first, under subheaders), and
    /// names each row's repository once it holds more than one project; a
    /// project's tab names it only when the project has several repositories.
    public func tabContent(for tab: MenuTab) -> MenuTabContent {
        let tab = resolved(tab)
        let visible: [MenuSection] = switch tab {
        case .all: sections
        case .project(let name): sections.filter { $0.name == name }
        }
        let groups: [RowGroup]
        switch tab {
        case .all:
            var seen = Set<String>()
            let rows = visible.flatMap(\.rows).filter { seen.insert($0.id).inserted }
            groups = Arrangement.groups(
                rows: rows,
                project: "",
                settings: Self.allTabArrangement,
                layout: .tabs,
                folded: foldedGroups,
                // Grouping by kind reads no dates.
                now: lastUpdated ?? .distantPast
            )
        case .project:
            groups = visible.flatMap(\.groups)
        }
        let errors = visible.flatMap(\.errors)
        return MenuTabContent(
            groups: groups,
            errors: errors,
            notes: visible.flatMap(\.notes),
            attentionCount: attentionCount(for: tab),
            projectCount: visible.count,
            showsRepository: tab == .all ? visible.count > 1 || visible.contains(where: \.showsRepository)
                : visible.contains(where: \.showsRepository),
            isLoaded: visible.allSatisfy(\.isLoaded)
        )
    }
}
