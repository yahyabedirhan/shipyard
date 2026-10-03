import ShipyardCommand
import ShipyardCore
import Testing

@Suite("Version")
struct VersionTests {
    @Test("the version is 0.1.0")
    func version() {
        #expect(ShipyardVersion.current == "0.1.0")
    }
}
