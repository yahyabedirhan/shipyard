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

/// Which row a layout highlights: at most one, the row under the pointer.
/// The layouts draw one highlight shape at this place and feed it the
/// pointer's enter and exit events, which can arrive out of order; the
/// rule for what they mean lives here, so it's tested without SwiftUI.
public struct RowHighlight: Equatable, Sendable {
    /// The highlighted row; `nil` when none is.
    public private(set) var place: MenuRowPlace?

    public init(place: MenuRowPlace? = nil) {
        self.place = place
    }

    public func isHighlighted(_ place: MenuRowPlace) -> Bool {
        self.place == place
    }

    /// The pointer entered a row: it's the highlighted one now.
    public mutating func pointerEntered(_ place: MenuRowPlace) {
        self.place = place
    }

    /// The pointer left a row. A late exit from a row the highlight has
    /// already moved on from changes nothing.
    public mutating func pointerExited(_ place: MenuRowPlace) {
        if self.place == place { self.place = nil }
    }

    /// The pointer left the rows altogether: nothing is highlighted, even
    /// if the last row's own exit never arrived.
    public mutating func pointerLeftRows() {
        place = nil
    }

    /// The rows changed (a refresh, a collapse, another tab): a highlighted
    /// row that's no longer among `places` loses the highlight.
    public mutating func keep(in places: [MenuRowPlace]) {
        if let place, !places.contains(place) { self.place = nil }
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
}

extension MenuTabContent {
    /// The tab's rows a highlight can rest on, top to bottom through its
    /// kind groups; error rows aren't items.
    public var rowPlaces: [MenuRowPlace] {
        groups.flatMap { group in group.rows.map { MenuRowPlace(section: nil, row: $0.id) } }
    }
}
