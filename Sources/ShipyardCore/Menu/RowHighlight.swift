import Foundation

/// Where a row sits in a layout: the project it's listed under and what's
/// there, an item, the project's header or a subsection's subheader. The
/// list layout can list one item under two projects, so its two rows have
/// two places and only the one under the pointer is highlighted.
public struct MenuRowPlace: Hashable, Sendable {
    /// What a place holds. A new stop for the keys is one more case.
    public enum Kind: Hashable, Sendable {
        /// An item: its `MenuRow.id`.
        case item(String)
        /// The list layout's header of the project in `section`.
        case projectHeader
        /// A subsection's subheader.
        case groupHeader(GroupID)
    }

    /// The project (section) the row is listed under in the list layout;
    /// `nil` in a tab, which lists each row once.
    public var section: String?
    public var kind: Kind

    public init(section: String?, row: String) {
        self.section = section
        kind = .item(row)
    }

    private init(section: String?, kind: Kind) {
        self.section = section
        self.kind = kind
    }

    /// The list layout's header of the project named `project`: a row the
    /// pointer and the keys highlight like an item.
    public static func header(_ project: String) -> MenuRowPlace {
        MenuRowPlace(section: project, kind: .projectHeader)
    }

    /// The subheader of the subsection `group`, under the project `section`
    /// in the list layout (`nil` in a tab): ↑ and ↓ stop on it, and ← and
    /// → fold it.
    public static func groupHeader(_ group: GroupID, in section: String?) -> MenuRowPlace {
        MenuRowPlace(section: section, kind: .groupHeader(group))
    }

    /// The item's `MenuRow.id`; `nil` for a header or a subheader.
    public var row: String? {
        if case .item(let id) = kind { id } else { nil }
    }

    /// The subsection whose subheader it is; `nil` for anything else.
    public var group: GroupID? {
        if case .groupHeader(let id) = kind { id } else { nil }
    }

    /// Whether it's a project's header (pinned in the list layout) rather
    /// than an item or a subheader.
    public var isHeader: Bool { kind == .projectHeader }
}

/// What ← or → asks of a layout besides moving the highlight: a project to
/// collapse or expand, or a subsection to fold or unfold.
public enum MenuFold: Equatable, Sendable {
    case collapse(String)
    case expand(String)
    case fold(GroupID)
    case unfold(GroupID)
}

/// Which row a layout highlights: at most one, moved by the pointer and by
/// the arrow keys. The layouts draw one highlight shape at this place
/// and feed it the pointer's enter and exit events, which can arrive out of
/// order, and the keys; the rule for what they mean lives here, so it's
/// tested without SwiftUI.
///
/// The pointer and the keys share the highlight. The keys continue from
/// the row the pointer highlighted; after a key, rows scrolling under a
/// resting pointer don't take the highlight back, until the pointer
/// itself moves (`pointerMoved()`), as in a menu.
public struct RowHighlight: Equatable, Sendable {
    /// The highlighted row; `nil` when none is.
    public private(set) var place: MenuRowPlace?
    /// The row under the pointer, from its enter and exit events.
    private var underPointer: MenuRowPlace?
    /// Whether the pointer drives the highlight; `false` after a key,
    /// until the pointer moves.
    public private(set) var followsPointer = true

    public init(place: MenuRowPlace? = nil) {
        self.place = place
    }

    public func isHighlighted(_ place: MenuRowPlace) -> Bool {
        self.place == place
    }

    // MARK: - The pointer

    /// The pointer entered a row (or a project's header): it's the
    /// highlighted one now (unless the keys hold the highlight and the row
    /// only scrolled under the pointer).
    public mutating func pointerEntered(_ place: MenuRowPlace) {
        underPointer = place
        if followsPointer { self.place = place }
    }

    /// The pointer left a row. A late exit from a row the highlight has
    /// already moved on from changes nothing.
    public mutating func pointerExited(_ place: MenuRowPlace) {
        if underPointer == place { underPointer = nil }
        if followsPointer, self.place == place { self.place = nil }
    }

    /// The pointer left the rows altogether, out of the list or onto an
    /// error row or a placeholder: nothing is highlighted, even if the last
    /// row's own exit never arrived.
    public mutating func pointerLeftRows() {
        underPointer = nil
        if followsPointer { place = nil }
    }

    /// The pointer moved (not the rows under it): it drives the highlight
    /// again, which goes to the row under it, or to none.
    public mutating func pointerMoved() {
        followsPointer = true
        place = underPointer
    }

    // MARK: - ↑ and ↓

    /// ↓: the row after the highlighted one in `places` (the layout's rows,
    /// top to bottom), or the first when none is highlighted or the
    /// highlighted row is gone; from the last row, the first, as in a menu.
    public mutating func moveDown(in places: [MenuRowPlace]) {
        move(in: places, by: 1)
    }

    /// ↑: the row before the highlighted one, or the last when none is
    /// highlighted or the highlighted row is gone; from the first row, the
    /// last.
    public mutating func moveUp(in places: [MenuRowPlace]) {
        move(in: places, by: -1)
    }

    /// The first of `places`, or none when there are none: where the keys
    /// start in a tab they just switched to.
    public mutating func moveToFirst(in places: [MenuRowPlace]) {
        followsPointer = false
        place = places.first
    }

    private mutating func move(in places: [MenuRowPlace], by step: Int) {
        guard !places.isEmpty else { return }
        followsPointer = false
        guard let place, let index = places.firstIndex(of: place) else {
            self.place = step > 0 ? places.first : places.last
            return
        }
        let count = places.count
        self.place = places[((index + step) % count + count) % count]
    }

    // MARK: - ← and → in the list layout

    /// ←, as in an outline: from an item to its subsection's subheader, or
    /// to its project's header when its group has none; on an open
    /// subheader, folds it; from a folded one to its project's header; on
    /// an expanded header, collapses its project. What folds keeps the
    /// highlight. Returns what to fold, if anything. On a collapsed header,
    /// with nothing highlighted, or on a project that's gone, nothing happens.
    public mutating func moveLeft(in model: MenuModel) -> MenuFold? {
        guard let place, let project = place.section,
              let section = model.sections.first(where: { $0.name == project }) else { return nil }
        switch place.kind {
        case .item(let id):
            let group = section.groups.first { $0.rows.contains { $0.id == id } }
            moveTo(group.flatMap { $0.showsHeader ? .groupHeader($0.id, in: project) : nil } ?? .header(project))
            return nil
        case .groupHeader(let id):
            guard let group = section.groups.first(where: { $0.id == id }) else { return nil }
            if let fold = foldLeft(group) { return fold }
            moveTo(.header(project))
            return nil
        case .projectHeader:
            guard !section.isCollapsed else { return nil }
            followsPointer = false
            return .collapse(project)
        }
    }

    /// →: on a collapsed header, expands its project; on an expanded one,
    /// goes to what's first under it (a subheader or an item); on a folded
    /// subheader, unfolds it; on an open one, goes to its first item. What
    /// unfolds keeps the highlight. Returns what to unfold, if anything. On
    /// an item, a header or subheader with nothing under it, or with nothing
    /// highlighted, nothing happens.
    public mutating func moveRight(in model: MenuModel) -> MenuFold? {
        guard let place, let project = place.section,
              let section = model.sections.first(where: { $0.name == project }) else { return nil }
        switch place.kind {
        case .item:
            return nil
        case .groupHeader(let id):
            guard let group = section.groups.first(where: { $0.id == id }) else { return nil }
            return foldRight(group, in: project)
        case .projectHeader:
            if section.isCollapsed {
                followsPointer = false
                return .expand(project)
            }
            let places = model.listRowPlaces
            guard let index = places.firstIndex(of: place), index + 1 < places.count,
                  places[index + 1].section == project else { return nil }
            moveTo(places[index + 1])
            return nil
        }
    }

    // MARK: - ← and → on a tab's subheader

    /// ← on a tab's subheader: folds it if it's open. Returns the group
    /// to fold, if any; anywhere else in the tab, nothing happens (← there
    /// switches tabs).
    public mutating func moveLeft(in content: MenuTabContent) -> MenuFold? {
        guard let id = place?.group, let group = content.groups.first(where: { $0.id == id }) else { return nil }
        return foldLeft(group)
    }

    /// → on a tab's subheader: unfolds a folded one, or goes to an open
    /// one's first item. Returns the group to unfold, if any; anywhere else
    /// in the tab, nothing happens (→ there switches tabs).
    public mutating func moveRight(in content: MenuTabContent) -> MenuFold? {
        guard let id = place?.group, let group = content.groups.first(where: { $0.id == id }) else { return nil }
        return foldRight(group, in: nil)
    }

    // MARK: - Folding a subsection

    /// ← on `group`'s subheader: folds it unless it's folded already.
    private mutating func foldLeft(_ group: RowGroup) -> MenuFold? {
        guard !group.isFolded else { return nil }
        followsPointer = false
        return .fold(group.id)
    }

    /// → on `group`'s subheader, listed under `section`: unfolds it, or goes
    /// to its first item.
    private mutating func foldRight(_ group: RowGroup, in section: String?) -> MenuFold? {
        if group.isFolded {
            followsPointer = false
            return .unfold(group.id)
        }
        if let first = group.rows.first { moveTo(MenuRowPlace(section: section, row: first.id)) }
        return nil
    }

    /// The keys move the highlight to `place`.
    private mutating func moveTo(_ place: MenuRowPlace) {
        followsPointer = false
        self.place = place
    }

    // MARK: - The rows

    /// The rows changed (a refresh, a collapse, another tab): a highlighted
    /// row that's no longer among `places` loses the highlight.
    public mutating func keep(in places: [MenuRowPlace]) {
        if let place, !places.contains(place) { self.place = nil }
        if let underPointer, !places.contains(underPointer) { self.underPointer = nil }
    }
}

/// What Return acts on in the list layout: an item, which it opens (⌥Return
/// marks it seen), a project's header, which opens the project's
/// repository on GitHub, or a subsection's subheader, which it folds or
/// unfolds, as a click does.
public enum MenuListTarget: Equatable, Sendable {
    case item(MenuRow)
    case project(MenuSection)
    case group(RowGroup)
}

extension RowGroup {
    /// The group's places a highlight can rest on, top to bottom, listed
    /// under `section` (`nil` in a tab): its subheader if it has one, then,
    /// unless it's folded, its rows.
    public func places(in section: String?) -> [MenuRowPlace] {
        (showsHeader ? [.groupHeader(id, in: section)] : [])
            + (isFolded ? [] : rows.map { MenuRowPlace(section: section, row: $0.id) })
    }

    /// Its row with the id `id`, unless it's folded away.
    func visibleRow(_ id: String) -> MenuRow? {
        isFolded ? nil : rows.first { $0.id == id }
    }
}

extension MenuModel {
    /// The list layout's rows a highlight can rest on, top to bottom: each
    /// project's header, then, while it's expanded, its groups' subheaders
    /// and the rows of the ones that aren't folded. A collapsed project
    /// gives only its header; error and not-loaded placeholder rows aren't
    /// rows.
    public var listRowPlaces: [MenuRowPlace] {
        sections.flatMap { section in
            [MenuRowPlace.header(section.name)]
                + (section.isCollapsed ? [] : section.groups.flatMap { $0.places(in: section.name) })
        }
    }

    /// What Return acts on at `place`: the project of a header, a
    /// subheader's group, or an item if its project is expanded and its
    /// group open, and it's still listed.
    public func listTarget(at place: MenuRowPlace) -> MenuListTarget? {
        guard let section = sections.first(where: { $0.name == place.section }) else { return nil }
        switch place.kind {
        case .projectHeader:
            return .project(section)
        case .groupHeader(let id):
            guard !section.isCollapsed, let group = section.groups.first(where: { $0.id == id && $0.showsHeader }) else { return nil }
            return .group(group)
        case .item(let id):
            guard !section.isCollapsed, let row = section.groups.lazy.compactMap({ $0.visibleRow(id) }).first else { return nil }
            return .item(row)
        }
    }
}

extension MenuTabContent {
    /// The tab's rows a highlight can rest on, top to bottom through its
    /// groups: each subheader, then the rows of an open group; error rows
    /// aren't items.
    public var rowPlaces: [MenuRowPlace] {
        groups.flatMap { $0.places(in: nil) }
    }

    /// The tab's row at `place` (what Return opens), if it still lists it
    /// and its group isn't folded.
    public func row(at place: MenuRowPlace) -> MenuRow? {
        guard let id = place.row else { return nil }
        return groups.lazy.compactMap { $0.visibleRow(id) }.first
    }

    /// The subsection whose subheader is at `place` (what Return folds or
    /// unfolds), if the tab still lists it.
    public func subsection(at place: MenuRowPlace) -> RowGroup? {
        groups.first { $0.id == place.group && $0.showsHeader }
    }
}
