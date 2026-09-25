import Foundation
import ShipyardCore
import Testing

@Suite("Skill installer")
struct SkillInstallerTests {
    private let command = "npx -y skills add yahyabedirhan/shipyard -g -y"

    @Test("runs the command through the user's login shell, interactive")
    func runsThroughLoginShell() async {
        let shell = FakeShell(ShellOutput(status: 0, output: ""))
        let installer = SkillInstaller(environment: ["SHELL": "/opt/homebrew/bin/fish"], runner: shell)
        _ = await installer.install()
        #expect(shell.invocations == [
            ShellInvocation(executable: "/opt/homebrew/bin/fish", arguments: ["-l", "-i", "-c", command]),
        ])
        #expect(SkillInstaller.command == command)
    }

    @Test("falls back to zsh when $SHELL is missing, empty or not a path", arguments: [
        [:], ["SHELL": ""], ["SHELL": "zsh"],
    ])
    func fallbackShell(environment: [String: String]) async {
        let shell = FakeShell(ShellOutput(status: 0, output: ""))
        _ = await SkillInstaller(environment: environment, runner: shell).install()
        #expect(shell.invocations.map(\.executable) == ["/bin/zsh"])
    }

    @Test("a zero exit is installed, with the output cleaned of colour codes")
    func installed() async {
        let output = "\u{1B}[32m✓\u{1B}[0m Installed 1 skill: shipyard\n\n"
        let result = await SkillInstaller(environment: ["SHELL": "/bin/zsh"], runner: FakeShell(ShellOutput(status: 0, output: output))).install()
        #expect(result == .installed(output: "✓ Installed 1 skill: shipyard"))
    }

    @Test("a failing command reports what it printed")
    func failed() async {
        let output = "npm ERR! code ENOTFOUND\nnpm ERR! network request failed\n"
        let result = await SkillInstaller(environment: ["SHELL": "/bin/zsh"], runner: FakeShell(ShellOutput(status: 1, output: output))).install()
        #expect(result == .failed(output: "npm ERR! code ENOTFOUND\nnpm ERR! network request failed"))
    }

    @Test("a silent failure still says what failed")
    func silentFailure() async {
        let result = await SkillInstaller(environment: ["SHELL": "/bin/zsh"], runner: FakeShell(ShellOutput(status: 2, output: " \n"))).install()
        #expect(result == .failed(output: "`\(command)` exited with status 2"))
    }

    @Test("no npx in the login shell offers the command to copy", arguments: [
        "zsh:1: command not found: npx\n",
        "bash: line 1: npx: command not found\n",
        "",
    ])
    func npxNotFound(output: String) async {
        let result = await SkillInstaller(environment: ["SHELL": "/bin/zsh"], runner: FakeShell(ShellOutput(status: 127, output: output))).install()
        #expect(result == .npxNotFound(command: command))
    }

    @Test("a shell that can't be started is a failure naming it")
    func shellWontStart() async {
        let result = await SkillInstaller(environment: ["SHELL": "/bin/nosuchshell"], runner: FakeShell(nil)).install()
        #expect(result == .failed(output: "couldn't start /bin/nosuchshell"))
    }

    @Test("the process runner returns output from both streams and the status")
    func processRunner() async throws {
        let runner = ProcessShellRunner()
        let result = try #require(await runner.run(ShellInvocation(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"])))
        #expect(result.status == 3)
        #expect(result.output.contains("out"))
        #expect(result.output.contains("err"))
        #expect(await runner.run(ShellInvocation(executable: "/nonexistent/shell", arguments: [])) == nil)
    }

    @Test("cancelling the process runner stops the shell")
    func processRunnerCancelled() async {
        let started = Date()
        let run = Task {
            await ProcessShellRunner().run(ShellInvocation(executable: "/bin/sh", arguments: ["-c", "sleep 30"]))
        }
        try? await Task.sleep(for: .milliseconds(200))
        run.cancel()
        let result = await run.value
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(result?.status != 0)
    }

    @Test("cancelling stops an interactive shell (which ignores SIGTERM) and its children, which hold its output open")
    func processRunnerCancelledWithChildren() async throws {
        let marker = "31.\(Int.random(in: 1000...9999))"
        let started = Date()
        let run = Task {
            await ProcessShellRunner().run(ShellInvocation(executable: "/bin/sh", arguments: ["-i", "-c", "sleep \(marker) | cat; echo done"]))
        }
        try await Task.sleep(for: .milliseconds(500))
        run.cancel()
        _ = await run.value
        #expect(Date().timeIntervalSince(started) < 10)
        try await Task.sleep(for: .seconds(2))
        let check = try #require(await ProcessShellRunner().run(ShellInvocation(executable: "/bin/sh", arguments: ["-c", "ps -A -o command | grep 'sleep \(marker)' | grep -v grep"])))
        #expect(check.output.isEmpty)
    }
}
