import Foundation

/// What a command reads from where it runs: the working folder, the
/// environment variables (`XDG_CONFIG_HOME`, `HERDR_PANE_ID`, the
/// `HERDR_PLUGIN_EVENT`s), git, which says a folder's remote `origin`, and
/// how it runs a program (`herdr`) and tells whether one can be run. It
/// never names the platform: what differs between builds is chosen once,
/// when the executable assembles its `CommandTable`.
public struct CommandEnvironment: Sendable {
    public var workingDirectory: URL
    public var variables: [String: String]
    public var git: any GitRemoteLookup
    public var run: ProgramRun
    public var isExecutable: @Sendable (String) -> Bool

    public init(
        workingDirectory: URL,
        variables: [String: String],
        git: any GitRemoteLookup = GitCLI(),
        run: @escaping ProgramRun = ProgramRunner.process,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.workingDirectory = workingDirectory
        self.variables = variables
        self.git = git
        self.run = run
        self.isExecutable = isExecutable
    }
}
