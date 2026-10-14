import ShipyardCore
import SwiftUI

struct GroupHeader: View {
    let group: RowGroup
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions

    var body: some View {
        Button {
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
            .padding(.leading, Grid.gutter - 4)
            .padding(.trailing, Grid.gutter)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.title)
        .accessibilityHint(PanelText.groupFoldHelp(group))
        .accessibilityValue(PanelText.groupFoldState(group))
        .accessibilityAddTraits(.isHeader)
        .highlightable(place, $highlight)
        .padding(.top, Grid.gutter - 4)
    }
}

struct ShowMoreRow: View {
    let group: RowGroup
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

struct GroupDivider: View {
    var body: some View {
        Hairline()
            .padding(.leading, Grid.gutter + Grid.dotColumn + Grid.iconColumn)
            .padding(.trailing, Grid.gutter)
    }
}
