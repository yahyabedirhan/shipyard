import LabHost
import SwiftUI

/// The whole panel in the list layout, as the app draws it once ready, at
/// a light volume: header, pinned project headers over their rows, footer. Every click
/// works on fixture data: open marks a row seen, the layout button switches
/// to the list.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { ListAppPanel(volume: .light, layout: .list) }

struct ListAppPanel: View {
    @State private var store: LabStore

    init(volume: FixtureVolume, layout: MenuLayout) {
        _store = State(initialValue: LabStore(volume: volume, layout: layout))
    }

    var body: some View {
        LabPanel(store: store)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
