import Foundation
import ShipyardCommand

/// App control's commands for the Mac's `CommandTable`: `app` and `panel`, asking the
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
            support: support,
            client: ControlClient(socket: ControlSocket.locate(support: support), transport: transport),
            launcher: launcher,
            pause: pause
        )
        return [
            CommandTable.Entry(name: "app", help: appHelp) { arguments, environment, _ in
                switch ControlCommand.parse(arguments, environment: environment) {
                case .success(let invocation): ControlCommand.run(invocation, context: context)
                case .failure(let result): result
                }
            },
            CommandTable.Entry(name: "panel", help: panelHelp) { arguments, _, _ in
                switch PanelCommand.parse(arguments) {
                case .success(let request): ControlCommand.run(.send(request), context: context)
                case .failure(let result): result
                }
            },
        ]
    }

    static let appHelp = """
          app     open, quit or ask the Mac's shipyard app:
                  shipyard app open [--demo <folder>] | quit | status [--json]

        """

    static let panelHelp = """
          panel   steer the app's panel:
                  shipyard panel open | close | fold <project> | unfold <project>
                                 | show-more <project> <kind> | tab <name>

        """
}
