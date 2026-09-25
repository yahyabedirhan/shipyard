import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let userURL = Harness.userURL
private let viewerAnswer = Harness.viewerAnswer
private let unauthorized = Harness.unauthorized
private let withProjects = """
    [[projects]]
    name = "shipyard"
    repositories = ["yahyabedirhan/shipyard"]

    """

@Suite("Signing in")
@MainActor
struct SignInTests {
    // MARK: - Finding a token

    @Test("a token in the token store signs in without asking gh")
    func storedToken() async throws {
        let harness = try Harness(stored: "gho_stored", gh: "gho_fromgh")
        harness.stub.on(userURL, viewerAnswer)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.tokenSource == .tokenStore)
        #expect(harness.shipyard.viewer == Viewer(login: "yabepa", id: 42))
        #expect(harness.authorizations == ["Bearer gho_stored"])
        #expect(harness.gh.lookups == 0)
    }

    @Test("gh's token signs in silently when the token store is empty, straight to ready with projects")
    func ghToken() async throws {
        let harness = try Harness(gh: "gho_fromgh", config: withProjects)
        harness.stub.on(userURL, viewerAnswer)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.tokenSource == .gh)
        #expect(harness.authorizations == ["Bearer gho_fromgh"])
    }

    @Test("with no token anywhere, shipyard stays signed out and asks GitHub nothing")
    func noToken() async throws {
        let harness = try Harness()

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.tokenSource == nil)
        #expect(harness.gh.lookups == 1)
        #expect(harness.stub.requests.isEmpty)
    }

    @Test("a revoked stored token signs out and is dropped from the token store")
    func revokedStoredToken() async throws {
        let harness = try Harness(stored: "gho_revoked", config: withProjects)
        harness.stub.on(userURL, unauthorized)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.tokenSource == nil)
        #expect(try harness.store.token() == nil)
    }

    @Test("a revoked gh token signs out")
    func revokedGhToken() async throws {
        let harness = try Harness(gh: "gho_revoked")
        harness.stub.on(userURL, unauthorized)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
    }

    @Test("GitHub out of reach still signs in; the viewer waits for a later request")
    func offline() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, .failure())

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.viewer == nil)
    }

    // MARK: - A 401 from any request

    @Test("a 401 from a later request signs out and drops the stored token")
    func unauthorizedLater() async throws {
        let harness = try Harness(stored: "gho_stored", config: withProjects)
        harness.stub.on(userURL, viewerAnswer, unauthorized)
        await harness.shipyard.start()
        #expect(harness.shipyard.phase == .ready)

        await #expect(throws: GitHubError.unauthorized) {
            _ = try await harness.shipyard.request { try await $0.viewer() }
        }

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.viewer == nil)
        #expect(try harness.store.token() == nil)
    }

    @Test("other failures from a request leave shipyard signed in")
    func otherFailureKeepsSignedIn() async throws {
        let harness = try Harness(stored: "gho_stored", config: withProjects)
        harness.stub.on(userURL, viewerAnswer, .status(502))
        await harness.shipyard.start()

        await #expect(throws: GitHubError.http(502)) {
            _ = try await harness.shipyard.request { try await $0.viewer() }
        }

        #expect(harness.shipyard.phase == .ready)
        #expect(try harness.store.token() == "gho_stored")
    }

    // MARK: - Device flow

    @Test("the device flow shows the code while polling, then saves the token and signs in")
    func deviceFlowSignsIn() async throws {
        let harness = try Harness()
        let start = harness.sleeper.clock.now
        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code(interval: 5))
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.pending, DeviceFlowAnswers.token("gho_device"))
        harness.stub.on(userURL, viewerAnswer)
        let seen = Locked<[Phase]>([])
        let shipyard = harness.shipyard
        harness.sleeper.onSleep { _, _ in
            let phase = await shipyard.phase
            seen.withValue { $0.append(phase) }
        }

        await harness.shipyard.start()
        await harness.shipyard.beginDeviceFlow().value

        let code = DeviceCode(
            userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresAt: start.addingTimeInterval(900)
        )
        #expect(seen.current == [.connecting(code), .connecting(code)])
        #expect(try harness.store.token() == "gho_device")
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.tokenSource == .tokenStore)
        #expect(harness.shipyard.viewer == Viewer(login: "yabepa", id: 42))
        #expect(harness.authorizations == ["Bearer gho_device"])
        #expect(harness.shipyard.signInError == nil)
    }

    @Test("a code that expires ends the flow cleanly, and a new flow can start")
    func expiryAndRestart() async throws {
        let harness = try Harness(config: withProjects)
        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code(userCode: "FIRST-CODE"))
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.pending)
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signInError == .expired)
        #expect(try harness.store.token() == nil)

        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code(userCode: "SECOND-CODE"))
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.token("gho_second"))
        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.signInError == nil)
        #expect(try harness.store.token() == "gho_second")
        #expect(harness.stub.requests("POST", DeviceFlow.codeURL).count == 2)
    }

    @Test("the user declining returns to signed out with the reason")
    func denied() async throws {
        let harness = try Harness()
        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.denied)

        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signInError == .denied)
    }

    @Test("cancelling returns to signed out, stops polling and saves nothing")
    func cancel() async throws {
        let harness = try Harness()
        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.pending, DeviceFlowAnswers.token())
        let shipyard = harness.shipyard
        harness.sleeper.onSleep { index, _ in
            if index == 1 { await shipyard.cancelDeviceFlow() }
        }

        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signInError == nil)
        #expect(harness.stub.requests("POST", DeviceFlow.tokenURL).count == 1)
        #expect(try harness.store.token() == nil)
    }

    @Test("a device-flow token GitHub then rejects signs out")
    func deviceTokenRejected() async throws {
        let harness = try Harness()
        harness.stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        harness.stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.token("gho_bad"))
        harness.stub.on(userURL, unauthorized)

        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .signedOut)
        #expect(try harness.store.token() == nil)
    }

    @Test("the device flow only starts when signed out")
    func onlyWhenSignedOut() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        await harness.shipyard.beginDeviceFlow().value

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.stub.requests("POST", DeviceFlow.codeURL).isEmpty)
    }

    // MARK: - Signing out

    @Test("signing out clears the token store")
    func signOut() async throws {
        let harness = try Harness(stored: "gho_stored", config: withProjects)
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        let result = harness.shipyard.signOut()

        #expect(result == .signedOut)
        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.tokenSource == nil)
        #expect(harness.shipyard.viewer == nil)
        #expect(try harness.store.token() == nil)
    }

    @Test("signing out of a gh token says gh is still signed in")
    func signOutOfGh() async throws {
        let harness = try Harness(gh: "gho_fromgh")
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        #expect(harness.shipyard.signOut() == .ghStillSignedIn)
        #expect(harness.shipyard.phase == .signedOut)
    }

    // MARK: - Why shipyard is signed out (the connect screen)

    @Test("before the first look for a token there's no reason yet")
    func noReasonBeforeStart() throws {
        let harness = try Harness()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signedOutReason == nil)
    }

    @Test("with no gh token the reason is that there's no token")
    func reasonNoToken() async throws {
        let harness = try Harness()

        await harness.shipyard.start()

        #expect(harness.shipyard.signedOutReason == .noToken)
    }

    @Test("a gh token signs in with no reason left")
    func reasonClearedBySigningIn() async throws {
        let harness = try Harness(gh: "gho_fromgh", config: withProjects)
        harness.stub.on(userURL, viewerAnswer)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.signedOutReason == nil)
    }

    @Test("trying again once gh is signed in connects")
    func tryAgainAfterGhLogin() async throws {
        let harness = try Harness(config: withProjects)
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()
        #expect(harness.shipyard.signedOutReason == .noToken)

        harness.gh.set("gho_fromgh")
        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.tokenSource == .gh)
        #expect(harness.shipyard.signedOutReason == nil)
        #expect(harness.authorizations == ["Bearer gho_fromgh"])
    }

    @Test("a gh token GitHub rejects at start gives the rejected reason")
    func reasonRejectedAtStart() async throws {
        let harness = try Harness(gh: "gho_revoked")
        harness.stub.on(userURL, unauthorized)

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signedOutReason == .rejected(.gh))
    }

    @Test("a gh token revoked while signed in brings back the connect screen with the rejected reason")
    func reasonRejectedLater() async throws {
        let harness = try Harness(gh: "gho_fromgh", config: withProjects)
        harness.stub.on(userURL, viewerAnswer, unauthorized)
        await harness.shipyard.start()
        #expect(harness.shipyard.phase == .ready)

        _ = try? await harness.shipyard.request { try await $0.viewer() }

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.signedOutReason == .rejected(.gh))
    }

    @Test("signing out of gh's token keeps the reason: gh is still signed in")
    func reasonSignedOutOfGh() async throws {
        let harness = try Harness(gh: "gho_fromgh")
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        harness.shipyard.signOut()

        #expect(harness.shipyard.signedOutReason == .signedOut(.ghStillSignedIn))
    }

    @Test("signing out of a stored token gives the plain signed-out reason")
    func reasonSignedOutOfStore() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, viewerAnswer)
        await harness.shipyard.start()

        harness.shipyard.signOut()

        #expect(harness.shipyard.signedOutReason == .signedOut(.signedOut))
    }
}
