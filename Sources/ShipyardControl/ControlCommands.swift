import Foundation
import ShipyardCommand

/// App control's commands for the Mac's `CommandTable`: `app`, `panel`, `screenshot` and `control`, asking the
/// app whose support folder is `support` over `transport`, and launching
/// it with `launcher`. Each request is sent as the holder `Holder.find`
/// works out from the command's environment and `processes`.
public enum ControlCommands {
    public static func entries(
        support: URL,
        launcher: any AppLaunching,
        transport: any ControlTransport = UnixSocketTransport(),
        processes: any ProcessTable = SystemProcessTable(),
        pause: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> [CommandTable.Entry] {
        let context = { @Sendable (environment: CommandEnvironment) in
            ControlCommand.Context(
                support: support,
                client: ControlClient(
                    socket: ControlSocket.locate(support: support),
                    holder: Holder.find(variables: environment.variables, workingDirectory: environment.workingDirectory, processes: processes),
                    transport: transport
                ),
                launcher: launcher,
                pause: pause
            )
        }
        return [
            CommandTable.Entry(name: "app", help: appHelp) { arguments, environment, _ in
                switch ControlCommand.parse(arguments, environment: environment) {
                case .success(let invocation): ControlCommand.run(invocation, context: context(environment))
                case .failure(let result): result
                }
            },
            CommandTable.Entry(name: "panel", help: panelHelp) { arguments, environment, _ in
                switch PanelCommand.parse(arguments) {
                case .success(let request): ControlCommand.run(.send(request), context: context(environment))
                case .failure(let result): result
                }
            },
            CommandTable.Entry(name: "screenshot", help: screenshotHelp) { arguments, environment, _ in
                switch ScreenshotCommand.parse(arguments, workingDirectory: environment.workingDirectory) {
                case .success(let request): ControlCommand.run(.send(request), context: context(environment))
                case .failure(let result): result
                }
            },
            CommandTable.Entry(name: "control", help: controlHelp) { arguments, environment, _ in
                switch LeaseCommand.parse(arguments) {
                case .success(let invocation):
                    var context = context(environment)
                    // `--key` names the holder for this command only, over
                    // `SHIPYARD_CONTROL_KEY`.
                    if let key = invocation.key { context.client.holder.key = key }
                    return ControlCommand.run(.send(invocation.request), context: context)
                case .failure(let result):
                    return result
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

    static let screenshotHelp = """
          screenshot
                  save the app's panel, or its menu bar icon, as a PNG:
                  shipyard screenshot <file.png> [--appearance light|dark] [--menu-bar-icon]
                                      [--with-indicator]

        """

    static let controlHelp = """
          control hold shipyard for a run of app control steps, or give it up:
                  shipyard control take [--wait <seconds>] [--key <k>] | release [--key <k>]

        """
}
