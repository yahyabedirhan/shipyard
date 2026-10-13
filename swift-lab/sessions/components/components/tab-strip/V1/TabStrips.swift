import LabHost
import SwiftUI

/// The tabs layout's pill strip: All and one pill per project with its
/// attention count; the selected pill slides, and with more tabs than fit
/// the track scrolls sideways with its ends faded. Click a pill.
public let variant = LabVariant { TabStripSheet() }

struct TabStripSheet: View {
    @State private var few = MenuTab.all
    @State private var many = MenuTab.all
    @State private var lots = MenuTab.project("harbor")
    private let fewModel = Fixtures.model(.light)
    private let manyModel = Fixtures.model(.maintainer)
    private let lotsModel = Fixtures.model(.extreme)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Specimen(title: "3 projects") { strip(fewModel, $few) }
            Specimen(title: "11 projects: scrolls, ends fade") { strip(manyModel, $many) }
            Specimen(title: "30 projects, one selected mid-way") { strip(lotsModel, $lots) }
        }
        .padding(24)
        .background(Palette.panel)
        .hoverHelpHost()
    }

    /// The strip as the tabs layout places it: inside the panel's width,
    /// in from its gutters.
    private func strip(_ model: MenuModel, _ selection: Binding<MenuTab>) -> some View {
        VStack(spacing: 0) {
            TabStrip(model: model, selection: selection.wrappedValue) { next in
                withAnimation(Motion.tab) { selection.wrappedValue = next }
            }
            .padding(.horizontal, Grid.gutter)
        }
        .frame(width: Grid.panelWidth)
    }
}
