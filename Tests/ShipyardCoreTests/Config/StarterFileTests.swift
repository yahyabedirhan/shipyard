import Foundation
@testable import ShipyardCore
import Testing

// The app creates `config.toml` with its commented header whenever it
// starts without one, and again when the Refresh button finds it gone.
// A file that exists is never touched.

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["acme/shop"]

    """

@MainActor
private func contents(_ harness: Harness) throws -> String {
    try String(contentsOf: harness.configURL, encoding: .utf8)
}

@Suite("The starter configuration file")
@MainActor
struct StarterFileTests {
    @Test("starting without a file creates it with the header, and the app waits for projects")
    func startCreates() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)

        await harness.shipyard.start()

        #expect(try contents(harness) == Configuration.header)
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configWarnings.isEmpty)
    }

    @Test("starting signed out still creates the file")
    func startSignedOutCreates() async throws {
        let harness = try Harness()

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(try contents(harness) == Configuration.header)
    }

    @Test("every start creates a missing file, not only the first one")
    func everyStartCreates() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        await harness.shipyard.start()
        try FileManager.default.removeItem(at: harness.configURL)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        await relaunched.shipyard.start()

        #expect(try contents(relaunched) == Configuration.header)
    }

    @Test("starting leaves an existing file untouched, with or without a header",
          arguments: ["", shop, Configuration.header + shop])
    func startKeepsExisting(existing: String) async throws {
        let harness = try Harness(config: existing)

        await harness.shipyard.start()

        #expect(try contents(harness) == existing)
    }

    @Test("Refresh creates a file gone missing, and refreshes")
    func refreshNowCreates() async throws {
        let harness = try await Harness.started(config: shop, graphQL: Harness.fixture("graphql-pull-requests.json"))
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.graphQLRequests.count == 1)
        try FileManager.default.removeItem(at: harness.configURL)

        await harness.shipyard.refreshNow()

        #expect(try contents(harness) == Configuration.header)
        #expect(harness.graphQLRequests.count == 2)
    }

    @Test("Refresh leaves an existing file untouched, and refreshes")
    func refreshNowKeepsExisting() async throws {
        let harness = try await Harness.started(config: shop, graphQL: Harness.fixture("graphql-pull-requests.json"))

        await harness.shipyard.refreshNow()

        #expect(try contents(harness) == shop)
        #expect(harness.graphQLRequests.count == 2)
    }
}
