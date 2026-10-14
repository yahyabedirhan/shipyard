import Foundation
import ShipyardCommand

/// App control's groups for the Mac's `CommandTable`: `app`, `panel`, `lease` and `notes`, asking the
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
            CommandTable.Entry(name: "app", section: .app, commands: appCommands) { arguments, environment, _ in
                if arguments.first == "capture" {
                    switch ScreenshotCommand.parse(Array(arguments.dropFirst()), workingDirectory: environment.workingDirectory) {
                    case .success(let request): return ControlCommand.run(.send(request), context: context(environment))
                    case .failure(let result): return result
                    }
                }
                switch ControlCommand.parse(arguments, environment: environment) {
                case .success(let invocation): return ControlCommand.run(invocation, context: context(environment))
                case .failure(let result): return result
                }
            },
            CommandTable.Entry(name: "panel", section: .app, commands: panelCommands) { arguments, environment, _ in
                switch PanelCommand.parse(arguments) {
                case .success(let request): ControlCommand.run(.send(request), context: context(environment))
                case .failure(let result): result
                }
            },
            CommandTable.Entry(name: "lease", section: .app, commands: leaseCommands) { arguments, environment, _ in
                switch LeaseCommand.parse(arguments) {
                case .success(let invocation):
                    var context = context(environment)
                    if let key = invocation.key { context.client.holder.key = key }
                    return ControlCommand.run(.send(invocation.request), context: context)
                case .failure(let result):
                    return result
                }
            },
            CommandTable.Entry(name: "notes", section: .checks, commands: notesCommands) { arguments, environment, _ in
                switch arguments {
                case ["check"]: ControlCommand.run(.send(.notesCheck), context: context(environment))
                case ["--help"], ["-h"], ["check", "--help"], ["check", "-h"]: CommandResult(output: notesUsage)
                case []: CommandResult(error: notesUsage, status: CommandResult.usageStatus)
                default: .usage("shipyard notes: unexpected `\(arguments.joined(separator: " "))`. Run `shipyard notes --help` for usage.")
                }
            },
        ]
    }

    public static let notesUsage = """
        Check that the app can read the notes workspace in Notion.

        Usage: shipyard notes check

        Reads the notes workspace the way the app does, through ntn's default
        workspace: each project's database under Shipyard Notes > Projects and
        its open notes. Prints one line per project, then every problem with
        the layout. It needs no lease.

        Exit codes: 1 when it finds an error, or shipyard isn't running.

        """

    static let appCommands = [
        CommandTable.Command("open [--demo <folder>]", "launch the app, or a demo run, and wait until it answers"),
        CommandTable.Command("quit", "quit the app and wait until it's gone"),
        CommandTable.Command("status [--json]", "print whether the app runs, its version, layout and projects"),
        CommandTable.Command("capture <file.png> [options]", "save the panel, or the menu bar icon, as a PNG"),
    ]

    static let panelCommands = [
        CommandTable.Command("open", "open the menu bar icon's panel"),
        CommandTable.Command("close", "close the panel"),
        CommandTable.Command("fold <project>", "collapse a project's section"),
        CommandTable.Command("unfold <project>", "expand a project's section"),
        CommandTable.Command("show-more <project> <kind>", "show every row of a project's group past its cap"),
        CommandTable.Command("show-tab <name>", "show a tab of the tabs layout"),
        CommandTable.Command("show-view <name>", "show a status view, or the projects again"),
    ]

    static let leaseCommands = [
        CommandTable.Command("take [options]", "hold app control for a run of steps, waiting in line with --wait"),
        CommandTable.Command("release [--key <k>]", "give app control up to the next agent"),
    ]

    static let notesCommands = [
        CommandTable.Command("check", "check that the app can read the notes workspace in Notion"),
    ]
}
