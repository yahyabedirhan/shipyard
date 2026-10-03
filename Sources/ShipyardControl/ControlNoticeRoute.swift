import Foundation
import ShipyardCommand
import ShipyardNotices

/// The Mac's way for a notice to reach the app: the running app's control
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

    public func deliver(_ notice: Notice, environment: CommandEnvironment) -> NoticeVerdict {
        let client = ControlClient(
            socket: ControlSocket.locate(support: support),
            holder: Holder.find(variables: environment.variables, workingDirectory: environment.workingDirectory, processes: processes),
            transport: transport,
            timeout: Self.timeout
        )
        switch client.send(.notify(notice)) {
        case .success(let reply) where reply.ok:
            return .shown
        case .success(let reply):
            return .refused(reply.error.isEmpty ? "shipyard refused the notice without saying why" : reply.error)
        case .failure(.notRunning):
            return .refused(Self.notRunning)
        case .failure(.timedOut(let seconds)):
            return .refused("shipyard didn't answer within \(Int(seconds)) seconds, so this notice may not have been shown")
        case .failure(.failed(let why)):
            return .refused("couldn't reach shipyard, so this notice wasn't shown: \(why)")
        }
    }
}
