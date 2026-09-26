import ShipyardCore
import SwiftUI

/// A subsection's subheader: the group's title in small capitals (a
/// repository or a login as written) and how many rows it holds. Shared by
/// both layouts; in a tab it's the kind header the tabs always had.
struct GroupHeader: View {
    let group: RowGroup

    var body: some View {
        HStack(spacing: 5) {
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
        .padding(.leading, Grid.gutter + Grid.dotColumn)
        .padding(.trailing, Grid.gutter)
        .padding(.top, Grid.gutter)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
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
