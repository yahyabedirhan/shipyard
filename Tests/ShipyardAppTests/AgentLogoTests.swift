import AppKit
import ShipyardCore
@testable import ShipyardApp
import Testing

@Suite("Agent logos")
@MainActor
struct AgentLogoTests {
    @Test("every known agent's logo loads from the app's resources, in light and dark mode", arguments: KnownAgent.allCases)
    func bundled(agent: KnownAgent) throws {
        for dark in [false, true] {
            let image = try #require(AgentLogoImage.image(for: agent, dark: dark), "\(agent) has no logo (dark: \(dark))")
            #expect(image.size.width > 0 && image.size.height > 0)
            #expect(image.isTemplate == (agent.logo.look == .template))
        }
    }
}
