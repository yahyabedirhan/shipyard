import Foundation

/// Where a row sits in a layout: the project it's listed under and the
/// row, or the project's header. The list layout can list one item under
/// two projects, so its two rows have two places and only the one under
/// the pointer is highlighted.
public struct MenuRowPlace: Hashable, Sendable {
    /// The project (section) the row is listed under in the list layout;
    /// `nil` in a tab, which lists each row once.
    public var section: String?
    /// The row's `MenuRow.id`; `nil` for the project's header.
    public var row: String?

    public init(section: String?, row: String) {
        self.section = section
        self.row = row
    }

    private init(header project: String) {
        section = project
        row = nil
    }

    /// The list layout's header of the project named `project`: a row the
    /// pointer and the keys highlight like an item (#45).
    public static func header(_ project: String) -> MenuRowPlace {
        MenuRowPlace(header: project)
    }

    /// Whether it's a project's header rather than an item.
    public var isHeader: Bool { row == nil }
}

/// What ← or → asks of the list layout besides moving the highlight: a
/// project to collapse or expand.
public enum ProjectFold: Equatable, Sendable {
    case collapse(String)
    case expand(String)

    /// The project it folds.
    public var project: String {
        switch self {
        case .collapse(let name), .expand(let name): name
        }
    }
}

/// Which row a layout highlights: at most one, moved by the pointer and by
/// the arrow keys (#45). The layouts draw one highlight shape at this place
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

    /// ←: from an item to its project's header; on an expanded header,
    /// collapses its project (the header stays highlighted). Returns the
    /// project to collapse, if any. On a collapsed header, with nothing
    /// highlighted, or on a project that's gone, nothing happens.
    public mutating func moveLeft(in model: MenuModel) -> ProjectFold? {
        guard let place, let project = place.section,
              let section = model.sections.first(where: { $0.name == project }) else { return nil }
        if !place.isHeader {
            followsPointer = false
            self.place = .header(project)
            return nil
        }
        guard !section.isCollapsed else { return nil }
        followsPointer = false
        return .collapse(project)
    }

    /// →: on a collapsed header, expands its project (the header stays
    /// highlighted); on an expanded header, goes to its first item. Returns
    /// the project to expand, if any. On an item, a header without items,
    /// or with nothing highlighted, nothing happens.
    public mutating func moveRight(in model: MenuModel) -> ProjectFold? {
        guard let place, place.isHeader, let project = place.section,
              let section = model.sections.first(where: { $0.name == project }) else { return nil }
        if section.isCollapsed {
            followsPointer = false
            return .expand(project)
        }
        guard let first = section.rows.first else { return nil }
        followsPointer = false
        self.place = MenuRowPlace(section: project, row: first.id)
        return nil
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
/// marks it seen), or a project's header, which opens the project's
/// repository on GitHub.
public enum MenuListTarget: Equatable, Sendable {
    case item(MenuRow)
    case project(MenuSection)
}

extension MenuModel {
    /// The list layout's rows a highlight can rest on, top to bottom: each
    /// project's header, then, while it's expanded, its rows in order. A
    /// collapsed project gives only its header; error and not-loaded
    /// placeholder rows aren't rows.
    public var listRowPlaces: [MenuRowPlace] {
        sections.flatMap { section in
            [MenuRowPlace.header(section.name)]
                + (section.isCollapsed ? [] : section.rows.map { MenuRowPlace(section: section.name, row: $0.id) })
        }
    }

    /// What Return acts on at `place`: the project of a header, or an item
    /// if its project is expanded and still lists it.
    public func listTarget(at place: MenuRowPlace) -> MenuListTarget? {
        guard let section = sections.first(where: { $0.name == place.section }) else { return nil }
        guard let id = place.row else { return .project(section) }
        guard !section.isCollapsed, let row = section.rows.first(where: { $0.id == id }) else { return nil }
        return .item(row)
    }
}

extension MenuTabContent {
    /// The tab's rows a highlight can rest on, top to bottom through its
    /// kind groups; error rows aren't items.
    public var rowPlaces: [MenuRowPlace] {
        groups.flatMap { group in group.rows.map { MenuRowPlace(section: nil, row: $0.id) } }
    }

    /// The tab's row at `place` (what Return opens), if it still lists it.
    public func row(at place: MenuRowPlace) -> MenuRow? {
        groups.lazy.flatMap(\.rows).first { $0.id == place.row }
    }
}
