import ShipyardCore
import SwiftUI

struct GroupHeader: View {
    let group: RowGroup
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions
    @Environment(\.panelStyle) private var style
    @Environment(\.panelScale) private var scale

    var body: some View {
        let tight = style == .list
        Button {
            actions.toggleGroup(group)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: tight ? 7 : 7.5, weight: tight ? .bold : .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .animation(Motion.collapse) { $0.rotationEffect(.degrees(group.isFolded ? 0 : 90)) }
                    .frame(width: style.dotColumn)
                    .padding(.trailing, -1)
                Text(PanelText.groupHeader(group))
                    .font(scale.eyebrow(style))
                    .tracking(tight ? 0.6 : 0.5)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(group.rows.count + group.hiddenCount))
                    .font(scale.eyebrow(style).monospacedDigit())
                    .foregroundStyle(ThemeColor.textTertiary)
                Spacer()
            }
            .foregroundStyle(ThemeColor.textSecondary)
            .padding(.leading, scale.grid.gutter - 4)
            .padding(.trailing, scale.grid.gutter)
            .padding(.vertical, tight ? 2 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(group.title)
        .accessibilityHint(PanelText.groupFoldHelp(group))
        .accessibilityValue(PanelText.groupFoldState(group))
        .accessibilityAddTraits(.isHeader)
        .highlightable(place, $highlight)
        .padding(.top, tight ? 6 : scale.grid.gutter - 4)
    }
}

struct ShowMoreRow: View {
    let group: RowGroup
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions
    @Environment(\.panelStyle) private var style
    @Environment(\.panelScale) private var scale

    var body: some View {
        Button {
            actions.toggleShowMore(group)
        } label: {
            HStack(spacing: 0) {
                Text(PanelText.showMore(group))
                    .font(scale.meta(style))
                    .foregroundStyle(ThemeColor.textSecondary)
                Spacer()
            }
            .padding(.leading, scale.grid.gutter + style.dotColumn + style.iconColumn)
            .padding(.trailing, scale.grid.gutter)
            .frame(height: scale.rowHeight(style))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(PanelText.showMore(group))
        .highlightable(place, $highlight)
    }
}

struct GroupDivider: View {
    @Environment(\.panelStyle) private var style
    @Environment(\.panelScale) private var scale

    var body: some View {
        Hairline()
            .padding(.leading, scale.grid.gutter + style.dotColumn + style.iconColumn)
            .padding(.trailing, scale.grid.gutter)
    }
}
