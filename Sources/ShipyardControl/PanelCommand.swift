import Foundation
import ShipyardCommand

/// `shipyard panel …`: its arguments read into the `ControlRequest` the
/// app answers. Only the arguments' shape is checked here; whether the
/// project, kind, tab or view exists is the app's to say, since only it knows
/// the menu (exit 1 with the valid names).
public enum PanelCommand {
    public static let usageText = """
        usage: shipyard panel open | close | fold <project> | unfold <project>
                            | show-more <project> <kind> | tab <name> | view <name>

          open        open the menu bar icon's panel
          close       close it
          fold        collapse a project's section; unfold expands it
          show-more   show every row of a project's group of one kind, past its
                      show-first cap, until the panel closes; <kind> is
                      pull-requests, issues, workflow-runs or pings
          tab         show a tab of the tabs layout: a project's name, or All
          view        show a status view in place of the projects: github,
                      notion, skill or cli; projects shows the projects again

        Each exits 1 when shipyard isn't running, or when the project, kind,
        tab or view doesn't exist, naming the ones that do.

        """

    /// Reads the arguments after `panel`. `--help` is the usage on standard
    /// output; anything that doesn't read is the usage on standard error,
    /// exit 2.
    public static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        let wanted: [String]
        let request: ([String]) -> ControlRequest
        switch subcommand {
        case "open": (wanted, request) = ([], { _ in .panelOpen })
        case "close": (wanted, request) = ([], { _ in .panelClose })
        case "fold": (wanted, request) = (["project"], { .panelFold(project: $0[0]) })
        case "unfold": (wanted, request) = (["project"], { .panelUnfold(project: $0[0]) })
        case "show-more": (wanted, request) = (["project", "kind"], { .panelShowMore(project: $0[0], kind: $0[1]) })
        case "tab": (wanted, request) = (["name"], { .panelTab(name: $0[0]) })
        case "view": (wanted, request) = (["name"], { .panelView(name: $0[0]) })
        default: return .failure(misread("shipyard panel: unknown command `\(subcommand)`"))
        }
        if rest.count < wanted.count {
            let missing = wanted[rest.count...].map { "<\($0)>" }.joined(separator: " ")
            return .failure(misread("shipyard panel \(subcommand): missing \(missing)"))
        }
        if rest.count > wanted.count {
            return .failure(misread("shipyard panel \(subcommand): unexpected `\(rest[wanted.count])`"))
        }
        return .success(request(rest))
    }

    /// `line`, then the usage, on standard error: exit 2.
    private static func misread(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n" + usageText, status: CommandResult.usageStatus)
    }
}
