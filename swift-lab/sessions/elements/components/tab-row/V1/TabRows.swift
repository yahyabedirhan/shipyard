import LabHost
import SwiftUI

/// The tabs layout's item row in every kind and state, with the row's
/// click, hover highlight and hover card (`itemRow`) as the tab gives them.
public let variant = LabVariant { TabRowSheet() }

struct TabRowSheet: View {
    @State private var highlight = RowHighlight()

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                ForEach(Gallery.rows, id: \.id) { row in
                    let place = MenuRowPlace(section: nil, row: row.id)
                    TabRow(row: row, showsRepository: true)
                        .itemRow(row, at: place, highlight: $highlight, showsRepository: true, actions: Gallery.actions)
                        .labID("row-\(row.number)-\(row.kind.commandName)")
                }
            }
            .padding(.vertical, 6)
            .rowHighlight(highlight)
        }
        .hoverHelpHost()
        .padding(20)
    }
}
