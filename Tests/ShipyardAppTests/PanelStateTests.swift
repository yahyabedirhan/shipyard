@testable import ShipyardApp
import ShipyardCore
import Testing

@Suite("Opening a status view")
@MainActor
struct PanelStateTests {
    @Test("opening a view starts its check once, as it opens rather than when it's drawn, so a closed panel's view and a screenshot's off-screen copy still end in a result")
    func opensAndLooks() {
        let state = PanelState()
        var looked: [SetupPart] = []
        state.lookAt = { looked.append($0) }

        state.show(.notion)
        state.show(.notion)
        #expect(state.openView == .notion)
        #expect(looked == [.notion])

        state.show(.cli)
        state.show(nil)
        state.show(.notion)
        #expect(state.openView == .notion)
        #expect(looked == [.notion, .cli, .notion])
    }
}
