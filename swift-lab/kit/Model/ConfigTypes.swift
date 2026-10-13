import Foundation

// The few `config.toml` types the panel's views read, copied from
// `Sources/ShipyardConfig/Configuration.swift`. The lab has no configuration
// file: fixtures set these directly.

/// `[menu] layout`.
public enum MenuLayout: String, CaseIterable, Sendable {
    case list
    case tabs

    public var next: MenuLayout {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return all[(index + 1) % all.count]
    }
}

/// `group-by`.
public enum GroupBy: String, CaseIterable, Sendable {
    case kind
    case repository
    case date
    case author
    case none
}

/// `sort-by`.
public enum SortBy: String, CaseIterable, Sendable {
    case updated
    case created
    case title
}

/// How a project's listed items are grouped, sorted and drawn.
public struct ArrangementSettings: Equatable, Sendable {
    public var groupBy: GroupBy = .kind
    public var subsections: Bool?
    public var sortBy: SortBy = .updated
    public var showFirst: Int = 0
    public init(groupBy: GroupBy = .kind, subsections: Bool? = nil, sortBy: SortBy = .updated, showFirst: Int = 0) {
        self.groupBy = groupBy
        self.subsections = subsections
        self.sortBy = sortBy
        self.showFirst = showFirst
    }
}
