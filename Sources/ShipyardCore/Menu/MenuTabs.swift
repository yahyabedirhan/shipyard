import Foundation

/// One tab of the tabs layout: every project, or one of them by name.
public enum MenuTab: Hashable, Sendable {
    case all
    case project(String)
}

/// What a tab of the tabs layout lists: its rows grouped by kind, its
/// projects' error rows, and what the line under the tab strip counts.
public struct MenuTabContent: Equatable, Sendable {
    /// Pull requests, then issues, then runs; a kind with no rows is left out.
    public var groups: [MenuKindGroup]
    /// One per repository of the tab's projects that couldn't be fetched.
    public var errors: [MenuErrorRow]
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

/// The rows of one kind in a tab, under a small header.
public struct MenuKindGroup: Equatable, Sendable, Identifiable {
    public var kind: ItemKind
    public var rows: [MenuRow]
    /// Rows in the group needing attention.
    public var attentionCount: Int

    public var id: ItemKind { kind }
}

extension MenuModel {
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

    /// What `tab` lists. All takes every project's rows in project order,
    /// a row listed in two projects once, and names each row's repository
    /// once it holds more than one project; a project's tab names it only
    /// when the project has several repositories.
    public func tabContent(for tab: MenuTab) -> MenuTabContent {
        let tab = resolved(tab)
        let visible: [MenuSection] = switch tab {
        case .all: sections
        case .project(let name): sections.filter { $0.name == name }
        }
        var seen = Set<String>()
        let rows = visible.flatMap(\.rows).filter { seen.insert($0.id).inserted }
        let groups = Self.kindOrder.compactMap { kind -> MenuKindGroup? in
            let ofKind = rows.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            return MenuKindGroup(kind: kind, rows: ofKind, attentionCount: ofKind.filter(\.needsAttention).count)
        }
        let errors = visible.flatMap(\.errors)
        return MenuTabContent(
            groups: groups,
            errors: errors,
            attentionCount: attentionCount(for: tab),
            projectCount: visible.count,
            showsRepository: tab == .all ? visible.count > 1 || visible.contains(where: \.showsRepository)
                : visible.contains(where: \.showsRepository),
            isLoaded: visible.allSatisfy(\.isLoaded)
        )
    }
}
