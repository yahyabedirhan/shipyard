import LabHost
import SwiftUI

/// The tabs layout at about the maintainer's volume (11 projects, ~420
/// rows in All), with no meter: the panel as it feels today. Hover and
/// scroll it; the perf session measures the same panel.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { BusyPanel() }

struct BusyPanel: View {
    @State private var store = LabStore(volume: .maintainer, layout: .tabs)

    var body: some View {
        LabPanel(store: store)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
