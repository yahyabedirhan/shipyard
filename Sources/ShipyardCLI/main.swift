import Foundation
import ShipyardCLISettings
import ShipyardCommand
import ShipyardPings
#if os(macOS)
import ShipyardConfig
import ShipyardControl
#endif

// `shipyard`: assembles this build's commands and prints what
// `ShipyardCLI.run` returns. The `#if` is decided at compile time, and so
// is what the build links (ADR 0006): on a machine without the app pings
// are kept as sent (`Unfiled`), on the Mac they're filed against
// config.toml, and the Mac's build controls the app (`app`). Each build
// also picks where its own settings file, cli.toml, is (ADR 0008): beside
// that config.toml on the Mac, in the XDG config folder elsewhere. Nothing
// after it asks the platform.
let environment = ProcessInfo.processInfo.environment
var table = CommandTable()
#if os(macOS)
// The config.toml the app recorded it reads, whatever this shell's
// `XDG_CONFIG_HOME`; the command's own lookup before the app has run. A
// demo run doesn't move it: without `SHIPYARD_SUPPORT_DIR` pings are filed
// against the user's own config.toml into their own store, and `app` finds
// the demo through the pointer `app open --demo` leaves (`ControlSocket.locate`).
let support = SupportFolder.app(environment: environment)
let configURL = ConfigLocation.current(environment: environment, support: support)
// The commands that read cli.toml take it with their entries.
let settings = CLISettingsFile.beside(config: configURL)
table.add(PingCommands.entries(
    filing: ProjectFiling(
        configURL: configURL,
        repositories: ResolvedRepositoriesStore(directory: support)
    ),
    store: PingStore(directory: PingStore.appDirectory(in: support))
))
table.add(ControlCommands.entries(support: support, launcher: WorkspaceLauncher()))
#else
// The commands that read cli.toml take it with their entries.
let settings = CLISettingsFile.withoutTheApp(environment: environment)
table.add(PingCommands.entries(
    filing: Unfiled(),
    store: PingStore(directory: PingStore.directoryWithoutTheApp(environment: environment))
))
#endif
let result = ShipyardCLI.run(
    Array(CommandLine.arguments.dropFirst()),
    table: table,
    environment: CommandEnvironment(
        workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        variables: environment
    ),
    now: Date()
)
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.status)
