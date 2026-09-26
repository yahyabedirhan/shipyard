import Foundation
import ShipyardCore
import Testing

/// A sleep that never ends until its task is cancelled: the timeout never fires.
private let neverTimesOut: Sleep = { _ in
    while true { try await Task.sleep(for: .seconds(3600)) }
}

@Suite("Skill installation")
@MainActor
struct SkillInstallationTests {
    private let environment = ["SHELL": "/bin/zsh"]

    @Test("install runs once and ends with the installer's result")
    func finished() async {
        let shell = FakeShell(ShellOutput(status: 127, output: "zsh:1: command not found: npx"))
        let installation = SkillInstallation(installer: SkillInstaller(environment: environment, runner: shell), sleep: neverTimesOut)
        #expect(installation.state == .idle)

        let run = installation.start()
        #expect(installation.state == .running)
        await run.value

        #expect(installation.state == .finished(.npxNotFound(command: SkillInstaller.command)))
        #expect(shell.invocations.count == 1)
    }

    @Test("a second install while one runs doesn't start another")
    func oneAtATime() async {
        let shell = HangingShell()
        let installation = SkillInstallation(installer: SkillInstaller(environment: environment, runner: shell), sleep: neverTimesOut)
        let first = installation.start()
        let second = installation.start()
        await Task.yield()
        installation.cancel()
        await first.value
        await second.value
        #expect(shell.started == 1)
    }

    @Test("an install that runs past the timeout is stopped and says so")
    func timedOut() async {
        let shell = HangingShell()
        let asked = Locked<[TimeInterval]>([])
        let installation = SkillInstallation(
            installer: SkillInstaller(environment: environment, runner: shell),
            timeout: 180,
            sleep: { seconds in asked.withValue { $0.append(seconds) } }
        )

        await installation.start().value

        #expect(installation.state == .timedOut(seconds: 180))
        #expect(asked.current == [180])
        #expect(shell.cancelled == 1)
    }

    @Test("cancel stops the install and goes back to the offer")
    func cancelled() async {
        let shell = HangingShell()
        let installation = SkillInstallation(installer: SkillInstaller(environment: environment, runner: shell), sleep: neverTimesOut)
        let run = installation.start()
        while shell.started == 0 { await Task.yield() }

        installation.cancel()
        await run.value

        #expect(installation.state == .idle)
        #expect(shell.cancelled == 1)
    }

    @Test("after a result, install runs again")
    func again() async {
        let shell = FakeShell(ShellOutput(status: 1, output: "npm ERR! network"))
        let installation = SkillInstallation(installer: SkillInstaller(environment: environment, runner: shell), sleep: neverTimesOut)
        await installation.start().value
        #expect(installation.state == .finished(.failed(output: "npm ERR! network")))
        await installation.start().value
        #expect(shell.invocations.count == 2)
    }

    @Test("cancel goes back to the offer at once, so Install starts a new install while the old one winds down")
    func installAfterCancel() async {
        let shell = HangingShell()
        let installation = SkillInstallation(installer: SkillInstaller(environment: environment, runner: shell), sleep: neverTimesOut)
        let first = installation.start()
        while shell.started == 0 { await Task.yield() }

        installation.cancel()
        #expect(installation.state == .idle)
        let second = installation.start()
        while shell.started < 2 { await Task.yield() }
        #expect(installation.state == .running)

        await first.value
        #expect(installation.state == .running)
        installation.cancel()
        await second.value
        #expect(installation.state == .idle)
    }
}
