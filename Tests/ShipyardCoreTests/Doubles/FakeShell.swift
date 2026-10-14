import ShipyardCommand
import ShipyardCore

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
