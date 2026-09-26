import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ShipyardCore
import Testing

/// GitHub's answers, as recorded from the device flow endpoints.
enum DeviceFlowAnswers {
    static func code(interval: Int = 5, expiresIn: Int = 900, userCode: String = "WDJB-MJHT") -> StubHTTP.Answer {
        .json("""
            {"device_code":"3584d83530557fdd1f46af8289938c8ef79f9dc5","user_code":"\(userCode)",\
            "verification_uri":"https://github.com/login/device","expires_in":\(expiresIn),"interval":\(interval)}
            """)
    }
    static let pending = StubHTTP.Answer.json(#"{"error":"authorization_pending","error_description":"The authorization request is still pending."}"#)
    static let slowDown = StubHTTP.Answer.json(#"{"error":"slow_down","error_description":"Too many requests.","interval":10}"#)
    static let expired = StubHTTP.Answer.json(#"{"error":"expired_token","error_description":"The device code has expired."}"#)
    static let denied = StubHTTP.Answer.json(#"{"error":"access_denied","error_description":"The user has denied your application access."}"#)
    static func token(_ token: String = "gho_16C7e42F292c6912E7710c838347Ae178B4a") -> StubHTTP.Answer {
        .json(#"{"access_token":"\#(token)","token_type":"bearer","scope":"repo,read:org"}"#)
    }
}

private func flow(_ stub: StubHTTP, _ sleeper: InstantSleeper, clientID: String = "test-client-id") -> DeviceFlow {
    DeviceFlow(clientID: clientID, transport: stub, clock: sleeper.clock, sleep: sleeper.sleep)
}

@Suite("Device flow")
struct DeviceFlowTests {
    @Test("requesting a code sends the client ID and scopes, and exposes the user code and verification URL")
    func requestCode() async throws {
        let stub = StubHTTP()
        stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        let clock = ManualClock()
        let authorization = try await flow(stub, InstantSleeper(clock: clock)).requestCode()

        #expect(authorization.code.userCode == "WDJB-MJHT")
        #expect(authorization.code.verificationURL == URL(string: "https://github.com/login/device")!)
        #expect(authorization.code.expiresAt == clock.now.addingTimeInterval(900))
        #expect(authorization.interval == 5)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.formFields == ["client_id": "test-client-id", "scope": "repo read:org"])
    }

    @Test("polls at the interval GitHub gave, adding 5 s on each slow_down, until the token comes")
    func pollsWithSlowDown() async throws {
        let stub = StubHTTP()
        stub.on("POST", DeviceFlow.tokenURL,
                DeviceFlowAnswers.pending, DeviceFlowAnswers.slowDown, DeviceFlowAnswers.pending,
                DeviceFlowAnswers.slowDown, DeviceFlowAnswers.token("gho_done"))
        let sleeper = InstantSleeper(clock: ManualClock())
        let authorization = DeviceAuthorization(
            deviceCode: "dev", code: DeviceCode(userCode: "U", verificationURL: URL(string: "https://github.com/login/device")!,
                                                 expiresAt: sleeper.clock.now.addingTimeInterval(900)),
            interval: 5
        )

        let token = try await flow(stub, sleeper).waitForToken(authorization)

        #expect(token == "gho_done")
        #expect(sleeper.slept == [5, 5, 10, 10, 15])
        let poll = try #require(stub.requests.first)
        #expect(poll.formFields == [
            "client_id": "test-client-id",
            "device_code": "dev",
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
    }

    @Test("stops with .expired once 15 minutes have passed without approval")
    func expiresAfterFifteenMinutes() async throws {
        let stub = StubHTTP()
        stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code(interval: 5))
        stub.on("POST", DeviceFlow.tokenURL, DeviceFlowAnswers.pending)
        let sleeper = InstantSleeper(clock: ManualClock())
        let device = flow(stub, sleeper)
        let start = sleeper.clock.now
        let authorization = try await device.requestCode()

        await #expect(throws: DeviceFlowError.expired) {
            _ = try await device.waitForToken(authorization)
        }
        #expect(sleeper.clock.now.timeIntervalSince(start) == 900)
        // Polled every 5 s before the 900 s mark, never after it.
        #expect(stub.requests("POST", DeviceFlow.tokenURL).count == 179)
    }

    @Test("GitHub's expired_token and access_denied end the flow")
    func githubEndsTheFlow() async throws {
        let cases: [(StubHTTP.Answer, DeviceFlowError)] = [(DeviceFlowAnswers.expired, .expired), (DeviceFlowAnswers.denied, .denied)]
        for (answer, error) in cases {
            let stub = StubHTTP()
            stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
            stub.on("POST", DeviceFlow.tokenURL, answer)
            let device = flow(stub, InstantSleeper(clock: ManualClock()))
            let authorization = try await device.requestCode()
            await #expect(throws: error) { _ = try await device.waitForToken(authorization) }
        }
    }

    @Test("GitHub refusing the code request, a 401, other statuses and no network are reported")
    func failures() async {
        let cases: [(StubHTTP.Answer, DeviceFlowError)] = [
            (.json(#"{"error":"device_flow_disabled"}"#), .rejected("device_flow_disabled")),
            (.status(401), .unauthorized),
            (.status(500), .http(500)),
            (.json("not json"), .malformed),
        ]
        for (answer, error) in cases {
            let stub = StubHTTP()
            stub.on("POST", DeviceFlow.codeURL, answer)
            await #expect(throws: error) {
                _ = try await flow(stub, InstantSleeper(clock: ManualClock())).requestCode()
            }
        }

        let offline = StubHTTP()
        offline.on("POST", DeviceFlow.codeURL, .failure())
        do {
            _ = try await flow(offline, InstantSleeper(clock: ManualClock())).requestCode()
            Issue.record("expected a network error")
        } catch let error as DeviceFlowError {
            guard case .network = error else { Issue.record("expected .network, got \(error)"); return }
        } catch {
            Issue.record("expected a DeviceFlowError, got \(error)")
        }
    }

    @Test("won't start while the client ID is still the placeholder")
    func placeholderClientID() async {
        let stub = StubHTTP()
        stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        await #expect(throws: DeviceFlowError.clientIDMissing) {
            _ = try await flow(stub, InstantSleeper(clock: ManualClock()), clientID: OAuthApp.placeholderClientID).requestCode()
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("uses the one compiled-in client ID unless given another")
    func defaultClientID() async throws {
        let stub = StubHTTP()
        stub.on("POST", DeviceFlow.codeURL, DeviceFlowAnswers.code())
        let device = DeviceFlow(transport: stub, clock: ManualClock())
        if OAuthApp.clientID == OAuthApp.placeholderClientID {
            await #expect(throws: DeviceFlowError.clientIDMissing) { _ = try await device.requestCode() }
        } else {
            _ = try await device.requestCode()
            #expect(stub.requests.first?.formFields["client_id"] == OAuthApp.clientID)
        }
    }
}
