import Foundation
import ShipyardCommand
import ShipyardPings
#if os(macOS)
import ShipyardCore
#endif

// `shipyard`: assembles this build's commands and prints what
// `ShipyardCLI.run` returns. The `#if` is decided at compile time, and so
// is what the build links (ADR 0006): on a machine without the app pings
// are kept as sent (`Unfiled`), on the Mac they're filed against
// config.toml. Nothing after it asks the platform.
let environment = ProcessInfo.processInfo.environment
var table = CommandTable()
#if os(macOS)
table.add(PingCommands.entries(
    filing: ProjectFiling(
        configURL: ConfigStore.defaultURL(environment: environment),
        repositories: ResolvedRepositoriesStore(directory: SupportFolder.app)
    ),
    store: PingStore(directory: PingStore.appDirectory)
))
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
