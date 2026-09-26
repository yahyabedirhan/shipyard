import Foundation

/// How a project's listed items are drawn: grouped by `group-by`, each
/// group sorted by `sort-by` with open (or running) items before closed (or
/// finished) ones, and each group shown under a subheader or after a
/// divider. Pure, so every rule is tested without SwiftUI.
public enum Arrangement {
    /// The groups `items` fall into for `project`, in order: kinds in the
    /// menu's kind order, repositories and authors A to Z, dates newest
    /// first; `none` makes one group. Empty groups are left out, so no
    /// items make no groups. Rows come without attention flags, which
    /// `MenuModel.applyAttention` sets.
    ///
    /// `folded` marks the subsections the user folded; `expanded` is for
    /// the groups shown past their cap.
    public static func groups(
        _ items: [Item],
        project: String,
        settings: ArrangementSettings,
        layout: MenuLayout,
        folded: Set<GroupID> = [],
        expanded: Set<GroupID> = [],
        now: Date,
        calendar: Calendar = .current
    ) -> [RowGroup] {
        groups(
            rows: items.map { MenuRow($0) },
            project: project,
            settings: settings,
            layout: layout,
            folded: folded,
            expanded: expanded,
            now: now,
            calendar: calendar
        )
    }

    /// `groups(_:…)` over rows that already carry their attention flags,
    /// each group counting its rows that need attention.
    static func groups(
        rows: [MenuRow],
        project: String,
        settings: ArrangementSettings,
        layout: MenuLayout,
        folded: Set<GroupID> = [],
        expanded: Set<GroupID> = [],
        now: Date,
        calendar: Calendar = .current
    ) -> [RowGroup] {
        let indexed = rows.enumerated().map { (offset: $0.offset, row: $0.element) }
        let buckets = Dictionary(grouping: indexed) { key(for: $0.row.item, settings: settings, now: now, calendar: calendar) }
        return buckets.keys.sorted(by: groupOrder).map { key in
            let sorted = buckets[key]!.sorted { comesFirst($0, $1, sortBy: settings.sortBy) }.map(\.row)
            let id = GroupID(project: project, key: key)
            let showsHeader = key != .ungrouped && (settings.subsections ?? layout.subheadersByDefault)
            return RowGroup(
                id: id,
                title: PanelText.groupTitle(key),
                rows: sorted,
                attentionCount: sorted.filter(\.needsAttention).count,
                showsHeader: showsHeader,
                isFolded: showsHeader && folded.contains(id),
                isExpanded: expanded.contains(id)
            )
        }
    }

    /// The group `item` falls into.
    static func key(for item: Item, settings: ArrangementSettings, now: Date, calendar: Calendar) -> GroupKey {
        switch settings.groupBy {
        case .kind: .kind(item.kind)
        case .repository: .repository(item.repository)
        case .date: .date(DateBucket(sortDate(item, settings.sortBy == .created ? .created : .updated), now: now, calendar: calendar))
        case .author: .author(item.author)
        case .none: .ungrouped
        }
    }

    /// The date an item sorts and buckets by: when it was created, or when
    /// it last changed (for a closed or finished one, when it closed).
    static func sortDate(_ item: Item, _ sortBy: SortBy) -> Date {
        switch sortBy {
        case .created: item.createdAt
        case .updated, .title: item.state.isActive ? item.updatedAt : (item.closedAt ?? item.updatedAt)
        }
    }

    /// Open (or running) first; then newest first, or A to Z by title
    /// (newest first between equal titles); then in the order given.
    private static func comesFirst(
        _ a: (offset: Int, row: MenuRow),
        _ b: (offset: Int, row: MenuRow),
        sortBy: SortBy
    ) -> Bool {
        let (left, right) = (a.row.item, b.row.item)
        if left.state.isActive != right.state.isActive { return left.state.isActive }
        if sortBy == .title {
            let order = left.title.localizedStandardCompare(right.title)
            if order != .orderedSame { return order == .orderedAscending }
        }
        let (leftDate, rightDate) = (sortDate(left, sortBy), sortDate(right, sortBy))
        if leftDate != rightDate { return leftDate > rightDate }
        return a.offset < b.offset
    }

    /// Kinds in the menu's kind order, dates newest first, repositories and
    /// authors A to Z ignoring case.
    private static func groupOrder(_ a: GroupKey, _ b: GroupKey) -> Bool {
        switch (a, b) {
        case (.kind(let left), .kind(let right)):
            MenuModel.kindOrder.firstIndex(of: left)! < MenuModel.kindOrder.firstIndex(of: right)!
        case (.date(let left), .date(let right)):
            left.rawValue < right.rawValue
        case (.repository(let left), .repository(let right)), (.author(let left), .author(let right)):
            left.lowercased() == right.lowercased() ? left < right : left.lowercased() < right.lowercased()
        default:
            // One project's groups all have the same kind of key.
            false
        }
    }
}

/// The key a group is known by: what its items share.
public enum GroupKey: Hashable, Sendable {
    case kind(ItemKind)
    /// `owner/name`
    case repository(String)
    case date(DateBucket)
    /// The author's login, without `@`.
    case author(String)
    /// The one group of `group-by = "none"`.
    case ungrouped
}

/// A group of one project (or of the All tab, whose project is empty): the
/// key a fold or an expansion is remembered by.
public struct GroupID: Hashable, Sendable {
    public var project: String
    public var key: GroupKey

    public init(project: String, key: GroupKey) {
        self.project = project
        self.key = key
    }
}

/// When an item last changed (or was created), counted in calendar days
/// back from now. Newest first.
public enum DateBucket: Int, CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    /// The bucket `date` falls into at `now`: the same day (or later, for a
    /// clock a little ahead), the day before, the same week, the same month,
    /// or earlier.
    public init(_ date: Date, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        self = if date >= today { .today }
            else if date >= yesterday { .yesterday }
            else if date >= week { .thisWeek }
            else if date >= month { .thisMonth }
            else { .older }
    }
}

/// One group of a project's rows, drawn under a subheader (a subsection)
/// or after a divider.
public struct RowGroup: Equatable, Sendable, Identifiable {
    public var id: GroupID
    /// "Pull requests", "owner/name", "Today", "@login"; empty for `none`.
    public var title: String
    /// Sorted: open (or running) first, then by `sort-by`.
    public var rows: [MenuRow]
    /// Rows in the group needing attention.
    public var attentionCount: Int
    /// Drawn under a subheader (its title and row count) rather than after
    /// a divider: `subsections`, or the layout's own when that's unset. The
    /// one group of `none` has no header.
    public var showsHeader: Bool
    /// Whether the user folded this subsection.
    public var isFolded: Bool
    /// Rows left out of `rows` by a cap.
    public var hiddenCount: Int
    /// Whether the user asked to see the group past its cap.
    public var isExpanded: Bool

    public init(
        id: GroupID,
        title: String,
        rows: [MenuRow],
        attentionCount: Int = 0,
        showsHeader: Bool = false,
        isFolded: Bool = false,
        hiddenCount: Int = 0,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.rows = rows
        self.attentionCount = attentionCount
        self.showsHeader = showsHeader
        self.isFolded = isFolded
        self.hiddenCount = hiddenCount
        self.isExpanded = isExpanded
    }
}

extension MenuLayout {
    /// Whether a group is drawn under a subheader when `subsections` is
    /// unset: in a tab it is, as the kind headers always were; the list
    /// draws a divider, as it always did.
    public var subheadersByDefault: Bool {
        switch self {
        case .list: false
        case .tabs: true
        }
    }
}
