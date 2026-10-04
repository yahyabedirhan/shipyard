import Foundation
import ShipyardCommand
import ShipyardNotices

/// The Mac's way for a notice, or its withdrawal, to reach the app: the running app's control
/// socket (`ControlRequest.notify`), as the holder `Holder.find` works out,
/// waiting for its verdict. It never launches the app: with the app not
/// running the notice is refused, so the agent knows nobody saw it.
public struct ControlNoticeRoute: NoticeRoute {
    private let support: URL
    private let transport: any ControlTransport
    private let processes: any ProcessTable

    /// How long it waits for the app's verdict: the app answers at once,
    /// so a longer wait means it's stuck, and the agent shouldn't be.
    public static let timeout: TimeInterval = 5

    /// The notice that couldn't be handed over, in words.
    public static let notRunning = "shipyard isn't running, so this notice wasn't shown"

    /// Asks the app whose support folder is `support` (or the demo it
    /// points at, `ControlSocket.locate`) over `transport`.
    public init(support: URL, transport: any ControlTransport = UnixSocketTransport(), processes: any ProcessTable = SystemProcessTable()) {
        self.support = support
        self.transport = transport
        self.processes = processes
    }

    /// The withdrawal that couldn't be handed over, in words.
    public static let notRunningToWithdraw = "shipyard isn't running, so the notice wasn't withdrawn"

    public func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict {
        let showing = if case .show = request { true } else { false }
        let client = ControlClient(
            socket: ControlSocket.locate(support: support),
            holder: Holder.find(variables: environment.variables, workingDirectory: environment.workingDirectory, processes: processes),
            transport: transport,
            timeout: Self.timeout
        )
        switch client.send(.notify(request)) {
        case .success(let reply) where reply.ok:
            return .shown
        case .success(let reply):
            return .refused(reply.error.isEmpty ? "shipyard refused the notice without saying why" : reply.error)
        case .failure(.notRunning):
            return .refused(showing ? Self.notRunning : Self.notRunningToWithdraw)
        case .failure(.timedOut(let seconds)):
            let outcome = showing ? "this notice may not have been shown" : "the notice may not have been withdrawn"
            return .refused("shipyard didn't answer within \(Int(seconds)) seconds, so \(outcome)")
        case .failure(.failed(let why)):
            let outcome = showing ? "this notice wasn't shown" : "the notice wasn't withdrawn"
            return .refused("couldn't reach shipyard, so \(outcome): \(why)")
        }
    }
}
