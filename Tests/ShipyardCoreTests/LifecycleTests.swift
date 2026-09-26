import Foundation
import ShipyardCore
import Testing

private let code = DeviceCode(
    userCode: "ABCD-1234",
    verificationURL: URL(string: "https://github.com/login/device")!,
    expiresAt: Date(timeIntervalSince1970: 1_790_000_900)
)

@Suite("Lifecycle")
struct LifecycleTests {
    @Test("signing in goes to the picker without projects, to ready with them")
    func signingIn() {
        #expect(Phase.signedOut.after(.signedIn(hasProjects: false)) == .needsProjects)
        #expect(Phase.signedOut.after(.signedIn(hasProjects: true)) == .ready)
        #expect(Phase.connecting(code).after(.signedIn(hasProjects: true)) == .ready)
    }

    @Test("the device flow shows its code, and cancelling returns to signed out")
    func deviceFlow() {
        let connecting = Phase.signedOut.after(.deviceFlowStarted(code))
        #expect(connecting == .connecting(code))
        #expect(connecting.after(.deviceFlowCancelled) == .signedOut)
    }

    @Test("projects added or emptied move between the picker and ready")
    func configurationChanges() {
        #expect(Phase.needsProjects.after(.configurationChanged(hasProjects: true)) == .ready)
        #expect(Phase.ready.after(.configurationChanged(hasProjects: false)) == .needsProjects)
        #expect(Phase.ready.after(.configurationChanged(hasProjects: true)) == .ready)
    }

    @Test("a configuration change doesn't sign anyone in", arguments: [Phase.signedOut, .connecting(code)])
    func configurationWhileSignedOut(phase: Phase) {
        #expect(phase.after(.configurationChanged(hasProjects: true)) == phase)
    }

    @Test("a 401 or sign out returns to signed out from anywhere",
          arguments: [Phase.signedOut, .connecting(code), .needsProjects, .ready])
    func signingOut(phase: Phase) {
        #expect(phase.after(.signedOut) == .signedOut)
    }

    @Test("events that don't apply leave the phase alone")
    func ignoredEvents() {
        #expect(Phase.ready.after(.deviceFlowStarted(code)) == .ready)
        #expect(Phase.ready.after(.signedIn(hasProjects: false)) == .ready)
        #expect(Phase.needsProjects.after(.deviceFlowCancelled) == .needsProjects)
    }

    @Test("only ready refreshes")
    func refreshing() {
        #expect(Phase.ready.canRefresh)
        #expect(!Phase.needsProjects.canRefresh)
        #expect(!Phase.signedOut.canRefresh)
        #expect(!Phase.connecting(code).canRefresh)
    }
}
