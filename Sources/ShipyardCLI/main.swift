import Foundation
import ShipyardCore

// `shipyard`: everything it does is `ShipyardCLI.run`, in the core, where
// tests reach it. This only gathers what it reads and prints what it says.
let environment = ProcessInfo.processInfo.environment
let result = ShipyardCLI.run(
    Array(CommandLine.arguments.dropFirst()),
    environment: CommandEnvironment(
        workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        variables: environment,
        platform: .current
    ),
    configURL: ConfigStore.defaultURL(environment: environment),
    repositories: ResolvedRepositoriesStore(directory: ResolvedRepositoriesStore.defaultDirectory),
    pingStore: PingStore(directory: PingStore.defaultDirectory(platform: .current, environment: environment)),
    now: Date()
)
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.status)
