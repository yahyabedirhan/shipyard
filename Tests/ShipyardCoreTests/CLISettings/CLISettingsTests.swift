import Foundation
import ShipyardCLISettings
import ShipyardCommand
import ShipyardConfig
import Testing

/// `cli.toml`, the `shipyard` command's own settings: where each build
/// finds it, a missing file read as the defaults, and a file that doesn't
/// read refused with exit 1 and what's wrong, as a command reading it hands
/// the agent.
@Suite("cli.toml, the command's own settings")
struct CLISettingsTests {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-cli-settings-\(UUID().uuidString)", isDirectory: true)
    var file: CLISettingsFile { CLISettingsFile(url: root.appendingPathComponent("cli.toml")) }

    func write(_ text: String) throws {
        try write(Data(text.utf8))
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: file.url)
    }

    /// What reading `file` hands a command: the settings, or its failure.
    func read() -> Result<CLISettings, CommandResult> {
        Result { () throws(CommandResult) in try file.read() }
    }

    // MARK: - Where it is

    @Test("without the app it's in the XDG config folder, ~/.config without one, as config.toml would be")
    func withoutTheApp() {
        let home = URL(fileURLWithPath: "/home/agent", isDirectory: true)
        #expect(CLISettingsFile.withoutTheApp(environment: [:], home: home).url.path == "/home/agent/.config/shipyard/cli.toml")
        #expect(CLISettingsFile.withoutTheApp(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).url.path == "/xdg/shipyard/cli.toml")
        #expect(CLISettingsFile.withoutTheApp(environment: ["XDG_CONFIG_HOME": "relative"], home: home).url.path == "/home/agent/.config/shipyard/cli.toml")
        #expect(CLISettingsFile.withoutTheApp(environment: ["XDG_CONFIG_HOME": ""], home: home).url.path == "/home/agent/.config/shipyard/cli.toml")
    }

    @Test("on the Mac it's beside the config.toml the app reads, wherever the app recorded that")
    func onTheMac() throws {
        let support = root.appendingPathComponent("support", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let mac = { CLISettingsFile.beside(config: ConfigLocation.current(environment: [:], home: home, support: support)) }
        #expect(mac().url.path == "/Users/me/.config/shipyard/cli.toml")
        try ConfigLocation.record(URL(fileURLWithPath: "/Users/me/dotfiles/shipyard/config.toml"), in: support)
        #expect(mac().url.path == "/Users/me/dotfiles/shipyard/cli.toml")
    }

    // MARK: - Reading it

    @Test("a missing file, an empty one and an empty [notify] are the defaults", arguments: [nil, "", "# nothing yet\n", "[notify]\n"])
    func defaults(text: String?) throws {
        if let text { try write(text) }
        #expect(try read().get() == .defaults)
    }

    @Test(
        "a file that doesn't read is refused with exit 1, its path and what's wrong",
        arguments: [
            ("[notify\n", "line 1: invalid TOML"),
            ("[notify]\napp-machin = \"mac\"\n", "unknown setting `notify.app-machin`"),
            ("[notfy]\n", "unknown setting `notfy`; known: `notify`"),
            ("notify = 3\n", "`notify` must be a table"),
        ]
    )
    func malformed(text: String, problem: String) throws {
        try write(text)
        let failure = try #require(read().failure)
        #expect(failure.status == CommandResult.failedStatus)
        #expect(failure.output.isEmpty)
        #expect(failure.error.hasPrefix("shipyard: \(file.url.path) doesn't read ("), "\(failure.error)")
        #expect(failure.error.contains(problem), "\(failure.error)")
        #expect(failure.error.hasSuffix("; fix it, then try again\n"))
    }

    // MARK: - [notify]

    @Test("[notify] names the app machine, and the scheme and port its notices go over, http and the listener's default port unless given", arguments: [
        ("[notify]\napp-machine = \"mac\"\n", NotifySettings(appMachine: "mac", appScheme: .http, appPort: 47420)),
        ("[notify]\napp-machine = \" my-mac.tail1234.ts.net \"\napp-scheme = \"https\"\napp-port = 443\n",
         NotifySettings(appMachine: "my-mac.tail1234.ts.net", appScheme: .https, appPort: 443)),
        // Without a machine, scheme and port wait for one.
        ("[notify]\napp-port = 8080\n", NotifySettings(appMachine: nil, appScheme: .http, appPort: 8080)),
    ])
    func notify(text: String, settings: NotifySettings) throws {
        try write(text)
        #expect(try read().get().notify == settings)
        #expect(CLISettings.defaults.notify == NotifySettings(appMachine: nil, appScheme: .http, appPort: 47420))
    }

    @Test("an app machine, scheme or port that can't make a URL is refused, saying what it takes", arguments: [
        ("app-machine = \"\"", "`notify.app-machine` names your Mac by its MagicDNS name, such as `my-mac`; leave it out to send notices no faster way"),
        ("app-machine = \"http://mac\"", "`notify.app-machine` is your Mac's MagicDNS name alone, such as `my-mac`, not `http://mac`: `app-scheme` and `app-port` are settings of their own"),
        ("app-machine = \"mac:8080\"", "`notify.app-machine` is your Mac's MagicDNS name alone, such as `my-mac`, not `mac:8080`"),
        ("app-machine = \"my mac\"", "`notify.app-machine` is your Mac's MagicDNS name alone, such as `my-mac`, not `my mac`"),
        ("app-machine = 3", "`notify.app-machine` must be a string"),
        ("app-scheme = \"ftp\"", "`notify.app-scheme` is `http` or `https`, not `ftp`"),
        ("app-port = 0", "`notify.app-port` must be between 1 and 65535 (got 0)"),
        ("app-port = 70000", "`notify.app-port` must be between 1 and 65535 (got 70000)"),
        ("app-port = \"80\"", "`notify.app-port` must be a whole number"),
        // config.toml's [notify] keys are the app's, never cli.toml's: no setting appears in both files.
        ("port = 443", "unknown setting `notify.port`; known: `app-machine`, `app-scheme`, `app-port`"),
    ])
    func badNotify(line: String, problem: String) throws {
        try write("[notify]\n\(line)\n")
        let failure = try #require(read().failure)
        #expect(failure.status == CommandResult.failedStatus)
        #expect(failure.error.contains(problem), "\(failure.error)")
    }

    @Test("a file that isn't UTF-8 text is refused too")
    func notText() throws {
        try write(Data([0xFF, 0xFE, 0x00]))
        let failure = try #require(read().failure)
        #expect(failure.status == CommandResult.failedStatus)
        #expect(failure.error.contains("the file isn't UTF-8 text"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
