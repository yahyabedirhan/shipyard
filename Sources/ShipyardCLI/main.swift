import Foundation
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
// config.toml, and the Mac's build controls the app (`app`). Nothing after
// it asks the platform.
let environment = ProcessInfo.processInfo.environment
var table = CommandTable()
#if os(macOS)
// The config.toml the app recorded it reads, whatever this shell's
// `XDG_CONFIG_HOME`; the command's own lookup before the app has run.
let support = SupportFolder.app
table.add(PingCommands.entries(
    filing: ProjectFiling(
        configURL: ConfigLocation.current(environment: environment, support: support),
        repositories: ResolvedRepositoriesStore(directory: support)
    ),
    store: PingStore(directory: PingStore.appDirectory)
))
table.add(ControlCommands.entries(support: SupportFolder.app, launcher: WorkspaceLauncher()))
#else
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
