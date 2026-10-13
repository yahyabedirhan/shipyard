import LabHost
import SwiftUI

/// The list layout's item row in every kind and state: number, title,
/// author or repository column, and age.
public let variant = LabVariant { ListRowSheet() }

struct ListRowSheet: View {
    @State private var highlight = RowHighlight()

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                ForEach(Gallery.rows, id: \.id) { row in
                    let place = MenuRowPlace(section: "harbor", row: row.id)
                    ListRow(row: row, showsRepository: false, widestNumber: "#999")
                        .itemRow(row, at: place, highlight: $highlight, showsRepository: false, actions: Gallery.actions)
                }
            }
            .padding(.vertical, 6)
            .rowHighlight(highlight)
        }
        .hoverHelpHost()
        .padding(20)
    }
}
