import Foundation
import ShipyardConfig
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private func answer(_ numbers: Int...) -> StubHTTP.Answer {
    PullRequestsResponse("yahyabedirhan/shop", numbers.map { PullRequestsResponse.PullRequest($0) }).answer
}

@MainActor
@Suite("The theme")
struct ThemeTests {
    @Test("the panel draws Shipyard without the key, and the theme the key names with it, from the first read")
    func configured() async throws {
        let plain = try await Harness.started(config: shop, graphQL: answer(1))
        #expect(plain.shipyard.theme == BuiltInThemes.shipyard)

        let paper = try await Harness.started(config: "theme = \"paper\"\n\n" + shop, graphQL: answer(1))
        #expect(paper.shipyard.theme == BuiltInThemes.named("Paper"))
    }

    @Test("changing the theme changes the panel's theme at once; an unknown name keeps it, with the configuration error")
    func liveChange() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1))

        try harness.writeConfig("theme = \"Midnight\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme == BuiltInThemes.named("Midnight"))

        try harness.writeConfig("theme = \"Midnigt\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError?.issues
            == [ConfigurationIssue(line: 1, message: "unknown theme `Midnigt` (did you mean `Midnight`?)")])
        #expect(harness.shipyard.theme == BuiltInThemes.named("Midnight"))

        try harness.writeConfig(shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme == BuiltInThemes.shipyard)
    }
}
