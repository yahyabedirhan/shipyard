import Foundation
import ShipyardCLISettings
import ShipyardCommand
import ShipyardNotices
import ShipyardPings
#if os(macOS)
import ShipyardConfig
import ShipyardControl
#endif

let environment = ProcessInfo.processInfo.environment
var table = CommandTable()
#if os(macOS)
let support = SupportFolder.app(environment: environment)
let configURL = ConfigurationLocation.current(environment: environment, support: support)
let settings = CLISettingsFile.beside(config: configURL)
table.add(PingCommands.entries(
    filing: ProjectFiling(
        configURL: configURL,
        repositories: ResolvedRepositoriesStore(directory: support)
    ),
    store: PingStore(directory: PingStore.appDirectory(in: support))
))
table.add(NoticeCommands.entries(route: ControlNoticeRoute(support: support)))
table.add(ControlCommands.entries(support: support, launcher: WorkspaceLauncher()))
table.add(ConfigurationCommands.entries(checks: [
    { now in ConfigurationStore.checks(configURL, at: now) },
    { now in [settings.check(at: now)] },
]))
#else
let settings = CLISettingsFile.withoutTheApp(environment: environment)
table.add(PingCommands.entries(
    filing: Unfiled(),
    store: PingStore(directory: PingStore.directoryWithoutTheApp(environment: environment))
))
table.add(NoticeCommands.entries(route: RemoteNoticeRoute(settings: settings)))
table.add(ConfigurationCommands.entries(checks: [{ now in [settings.check(at: now)] }]))
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
