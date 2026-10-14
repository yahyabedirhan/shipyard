import AppKit
import ShipyardCore
@testable import ShipyardApp
import Testing

@Suite("Service logos")
@MainActor
struct ServiceLogoTests {
    @Test("GitHub's and Notion's marks load from the app's resources as template images; the skill and the CLI have none", arguments: SetupPart.allCases)
    func bundled(part: SetupPart) throws {
        switch part {
        case .github, .notion:
            let image = try #require(SetupBadge.mark(for: part), "\(part) has no mark")
            #expect(image.size.width > 0 && image.size.height > 0)
            #expect(image.isTemplate)
        case .skill, .cli:
            #expect(SetupBadge.mark(for: part) == nil)
        }
    }
}
