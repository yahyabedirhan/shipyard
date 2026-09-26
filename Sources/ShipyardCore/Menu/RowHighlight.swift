import Foundation

/// Where a row sits in a layout: the project it's listed under and the
/// row. The list layout can list one item under two projects, so its two
/// rows have two places and only the one under the pointer is highlighted.
public struct MenuRowPlace: Hashable, Sendable {
    /// The project (section) the row is listed under in the list layout;
    /// `nil` in a tab, which lists each row once.
    public var section: String?
    /// The row's `MenuRow.id`.
    public var row: String

    public init(section: String?, row: String) {
        self.section = section
        self.row = row
    }
}

/// Which row a layout highlights: at most one, moved by the pointer and by
/// ↑ and ↓ (#45). The layouts draw one highlight shape at this place and
/// feed it the pointer's enter and exit events, which can arrive out of
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

    /// The pointer entered a row: it's the highlighted one now (unless the
    /// keys hold the highlight and the row only scrolled under the pointer).
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

    /// The pointer left the rows altogether, out of the list or onto a
    /// header or an error row: nothing is highlighted, even if the last
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

    // MARK: - The keys

    /// ↓: the row after the highlighted one in `places` (the layout's rows,
    /// top to bottom), or the first when none is highlighted or the
    /// highlighted row is gone; the last row stays.
    public mutating func moveDown(in places: [MenuRowPlace]) {
        move(in: places, by: 1)
    }

    /// ↑: the row before the highlighted one, or the last when none is
    /// highlighted or the highlighted row is gone; the first row stays.
    public mutating func moveUp(in places: [MenuRowPlace]) {
        move(in: places, by: -1)
    }

    private mutating func move(in places: [MenuRowPlace], by step: Int) {
        guard !places.isEmpty else { return }
        followsPointer = false
        guard let place, let index = places.firstIndex(of: place) else {
            self.place = step > 0 ? places.first : places.last
            return
        }
        self.place = places[min(max(index + step, 0), places.count - 1)]
    }

    // MARK: - The rows

    /// The rows changed (a refresh, a collapse, another tab): a highlighted
    /// row that's no longer among `places` loses the highlight.
    public mutating func keep(in places: [MenuRowPlace]) {
        if let place, !places.contains(place) { self.place = nil }
        if let underPointer, !places.contains(underPointer) { self.underPointer = nil }
    }
}

extension MenuModel {
    /// The list layout's rows a highlight can rest on, top to bottom: each
    /// expanded project's rows in order. Collapsed projects list none, and
    /// error and not-loaded placeholder rows aren't items.
    public var listRowPlaces: [MenuRowPlace] {
        sections.filter { !$0.isCollapsed }.flatMap { section in
            section.rows.map { MenuRowPlace(section: section.name, row: $0.id) }
        }
    }

    /// The list layout's row at `place` (what Return opens), if its project
    /// is expanded and still lists it.
    public func listRow(at place: MenuRowPlace) -> MenuRow? {
        sections.first { $0.name == place.section && !$0.isCollapsed }?
            .rows.first { $0.id == place.row }
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
