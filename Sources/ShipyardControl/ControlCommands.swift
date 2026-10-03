import Foundation
import ShipyardCommand

/// App control's commands for the Mac's `CommandTable`: `app`, asking the
/// app whose support folder is `support` over `transport`, and launching
/// it with `launcher`.
public enum ControlCommands {
    public static func entries(
        support: URL,
        launcher: any AppLaunching,
        transport: any ControlTransport = UnixSocketTransport(),
        pause: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> [CommandTable.Entry] {
        let context = ControlCommand.Context(
            client: ControlClient(socket: ControlSocket.locate(support: support), transport: transport),
            launcher: launcher,
            pause: pause
        )
        return [
            CommandTable.Entry(name: "app", help: appHelp) { arguments, _, _ in
                switch ControlCommand.parse(arguments) {
                case .success(let invocation): ControlCommand.run(invocation, context: context)
                case .failure(let result): result
                }
            },
        ]
    }

    static let appHelp = """
          app     open, quit or ask the Mac's shipyard app:
                  shipyard app open | quit | status [--json]

        """
}
