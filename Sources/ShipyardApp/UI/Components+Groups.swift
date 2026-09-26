import ShipyardCore
import SwiftUI

/// A subsection's subheader: a chevron, the group's title in small capitals
/// (a repository or a login as written) and how many rows it holds, folded
/// or not. A click folds or unfolds it, as ← and → do when the keys
/// highlight it; it's a place the highlight rests on, like a row. Shared by
/// both layouts; in a tab it's the kind header the tabs always had.
struct GroupHeader: View {
    let group: RowGroup
    /// Where it sits, for the highlight and the keys.
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions

    var body: some View {
        Button {
            // Not animated, like a project's fold (see `ListLayout.lineTransition`).
            actions.toggleGroup(group)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .animation(Motion.collapse) { $0.rotationEffect(.degrees(group.isFolded ? 0 : 90)) }
                    .frame(width: Grid.dotColumn)
                    .padding(.trailing, -1)
                Text(PanelText.groupHeader(group))
                    .font(TypeScale.eyebrow)
                    .tracking(0.5)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(group.rows.count + group.hiddenCount))
                    .font(TypeScale.eyebrow.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .foregroundStyle(.secondary)
            // The chevron in the rows' dot column, the title where it was.
            .padding(.leading, Grid.gutter - 4)
            .padding(.trailing, Grid.gutter)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(PanelText.groupFoldHelp(group))
        .accessibilityLabel(group.title)
        .accessibilityValue(PanelText.groupFoldState(group))
        .accessibilityAddTraits(.isHeader)
        .highlightable(place, $highlight)
        .padding(.top, Grid.gutter - 4)
    }
}

/// A capped group's last row: "Show 2 more", which shows the rest of the
/// group, then "Show less", which caps it again. A click toggles it, as
/// Return does when the keys highlight it; it's a place the highlight
/// rests on, like a row. Shared by both layouts, under subheaders or
/// dividers alike.
struct ShowMoreRow: View {
    let group: RowGroup
    /// Where it sits, for the highlight and the keys.
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions

    var body: some View {
        Button {
            actions.toggleShowMore(group)
        } label: {
            HStack(spacing: 0) {
                Text(PanelText.showMore(group))
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // Under the rows' titles.
            .padding(.leading, Grid.gutter + Grid.dotColumn + Grid.iconColumn)
            .padding(.trailing, Grid.gutter)
            .frame(height: Grid.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PanelText.showMore(group))
        .highlightable(place, $highlight)
    }
}

/// The line between two groups drawn without subheaders, indented to the
/// rows' titles.
struct GroupDivider: View {
    var body: some View {
        Hairline()
            .padding(.leading, Grid.gutter + Grid.dotColumn + Grid.iconColumn)
            .padding(.trailing, Grid.gutter)
    }
}
