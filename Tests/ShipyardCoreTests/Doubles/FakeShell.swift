import ShipyardCore

/// A `ShellRunning` standing in for spawning the login shell: records what
/// it was asked to run and answers with the output it was given (`nil` for
/// "the shell couldn't be started").
final class FakeShell: ShellRunning {
    private let answer: ShellOutput?
    private let runs = Locked<[ShellInvocation]>([])

    init(_ answer: ShellOutput?) { self.answer = answer }

    var invocations: [ShellInvocation] { runs.current }

    func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        runs.withValue { $0.append(invocation) }
        return answer
    }
}
