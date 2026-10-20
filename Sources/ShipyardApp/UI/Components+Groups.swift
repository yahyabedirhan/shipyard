import ShipyardCore
import SwiftUI

struct GroupHeader: View {
    let group: RowGroup
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions
    @Environment(\.panelStyle) private var style

    var body: some View {
        let tight = style == .list
        Button {
            actions.toggleGroup(group)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: tight ? 7 : 7.5, weight: .bold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .animation(Motion.collapse) { $0.rotationEffect(.degrees(group.isFolded ? 0 : 90)) }
                    .frame(width: style.dotColumn)
                    .padding(.trailing, -1)
                Text(PanelText.groupHeader(group))
                    .font(style.eyebrow)
                    .tracking(tight ? 0.6 : 0.5)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(group.rows.count + group.hiddenCount))
                    .font(style.eyebrow.monospacedDigit())
                    .foregroundStyle(ThemeColor.textTertiary)
                Spacer()
            }
            .foregroundStyle(ThemeColor.textSecondary)
            .padding(.leading, Grid.gutter - 4)
            .padding(.trailing, Grid.gutter)
            .padding(.vertical, tight ? 2 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(group.title)
        .accessibilityHint(PanelText.groupFoldHelp(group))
        .accessibilityValue(PanelText.groupFoldState(group))
        .accessibilityAddTraits(.isHeader)
        .highlightable(place, $highlight)
        .padding(.top, tight ? 6 : Grid.gutter - 4)
    }
}

struct ShowMoreRow: View {
    let group: RowGroup
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions
    @Environment(\.panelStyle) private var style

    var body: some View {
        Button {
            actions.toggleShowMore(group)
        } label: {
            HStack(spacing: 0) {
                Text(PanelText.showMore(group))
                    .font(style.meta)
                    .foregroundStyle(ThemeColor.textSecondary)
                Spacer()
            }
            .padding(.leading, Grid.gutter + style.dotColumn + style.iconColumn)
            .padding(.trailing, Grid.gutter)
            .frame(height: style.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(PanelText.showMore(group))
        .highlightable(place, $highlight)
    }
}

struct GroupDivider: View {
    @Environment(\.panelStyle) private var style

    var body: some View {
        Hairline()
            .padding(.leading, Grid.gutter + style.dotColumn + style.iconColumn)
            .padding(.trailing, Grid.gutter)
    }
}
