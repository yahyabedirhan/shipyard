import ShipyardCommand
import ShipyardCore
import Testing

@Suite("Version")
struct VersionTests {
    @Test("the version is 0.0.3")
    func version() {
        #expect(ShipyardVersion.current == "0.0.3")
    }
}
