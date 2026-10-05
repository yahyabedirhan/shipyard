import Foundation
import ShipyardCommand

/// `shipyard screenshot …`: its arguments read into the `ControlRequest`
/// the app answers. The path is made absolute here, against the folder the
/// command runs in, since the app runs in another one.
public enum ScreenshotCommand {
    public static let usageText = """
        usage: shipyard screenshot <file.png> [--appearance light|dark] [--menu-bar-icon]
                                  [--with-indicator]

          Saves shipyard's panel as it looks and prints the file's path. A
          closed panel isn't opened: it's rendered off screen instead, and
          that's said on standard error. A relative path is relative to this
          folder.
          The dot and the banner that show an agent holds shipyard are left
          out of it.

          --appearance      light or dark: the panel drawn in that appearance,
                            then back to the Mac's
          --menu-bar-icon   the menu bar icon alone instead of the panel
          --with-indicator  keeps the dot and the banner in the screenshot

        When the app can't capture its window, it renders the panel itself,
        writes that and says so on standard error, still exit 0. Exits 1 when
        shipyard isn't running or nothing could be written.

        """

    /// Reads the arguments after `screenshot`, a relative path resolved
    /// against `workingDirectory`. `--help` is the usage on standard
    /// output; anything that doesn't read is the usage on standard error,
    /// exit 2.
    public static func parse(_ arguments: [String], workingDirectory: URL) -> Result<ControlRequest, CommandResult> {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .failure(CommandResult(output: usageText))
        }
        var path: String?
        var appearance: ControlRequest.Appearance?
        var menuBarIcon = false
        var withIndicator = false
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--appearance":
                guard let name = rest.popFirst() else {
                    return .failure(misread("shipyard screenshot: --appearance needs light or dark"))
                }
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    return .failure(misread("shipyard screenshot: no appearance `\(name)`; it's light or dark"))
                }
                appearance = known
            case "--menu-bar-icon":
                menuBarIcon = true
            case "--with-indicator":
                withIndicator = true
            case let option where option.hasPrefix("-") && option.count > 1:
                return .failure(misread("shipyard screenshot: unknown option `\(option)`"))
            case let file where path == nil:
                path = file
            case let extra:
                return .failure(misread("shipyard screenshot: unexpected `\(extra)`"))
            }
        }
        guard let path else {
            return .failure(misread("shipyard screenshot: missing <file.png>"))
        }
        guard path.lowercased().hasSuffix(".png") else {
            return .failure(misread("shipyard screenshot: `\(path)` isn't a .png file"))
        }
        let absolute = URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL.path
        return .success(.screenshot(path: absolute, appearance: appearance, menuBarIcon: menuBarIcon, withIndicator: withIndicator))
    }

    /// `line`, then the usage, on standard error: exit 2.
    private static func misread(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n" + usageText, status: CommandResult.usageStatus)
    }
}
