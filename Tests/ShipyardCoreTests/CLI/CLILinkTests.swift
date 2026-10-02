import Foundation
import ShipyardCore
import Testing

/// The real file system, except that making a link fails as a folder
/// without write permission would.
private struct NoPermission: LinkFileSystem {
    struct Denied: LocalizedError {
        var errorDescription: String? { "You don't have permission to save the file “shipyard” in the folder “bin”" }
    }

    let real = FileManagerLinkFileSystem()
    func fileExists(at url: URL) -> Bool { real.fileExists(at: url) }
    func entry(at url: URL) -> LinkEntry { real.entry(at: url) }
    func createDirectory(at url: URL) throws { try real.createDirectory(at: url) }
    func createSymbolicLink(at url: URL, to destination: URL) throws { throw Denied() }
}

/// A file system with nothing in it, for the words alone.
private struct Empty: LinkFileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func entry(at url: URL) -> LinkEntry { .none }
    func createDirectory(at url: URL) throws {}
    func createSymbolicLink(at url: URL, to destination: URL) throws {}
}

/// A home folder and an app bundle with its CLI, in a fresh temporary folder.
private struct Sandbox {
    let root: URL
    let home: URL
    let cli: URL
    var link: URL { home.appendingPathComponent(".local/bin/shipyard") }

    init(cliPath: String = "Applications/Shipyard.app") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-cli-link-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        cli = CLILink.bundledCLI(in: root.appendingPathComponent(cliPath, isDirectory: true))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho shipyard\n".utf8).write(to: cli)
    }

    func makeBin() throws {
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func destination() throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Linking the CLI onto the PATH")
@MainActor
struct CLILinkTests {
    @Test("with nothing there it offers the link, then links ~/.local/bin/shipyard to the app's CLI, making the folder")
    func links() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        #expect(link.state == .unlinked)

        link.makeLink()

        #expect(link.state == .linked)
        #expect(try sandbox.destination() == sandbox.cli.path)
    }

    @Test("a link already pointing at this app's CLI is left alone and shows as linked")
    func alreadyLinked() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeBin()
        // A relative link to the same file counts too.
        let relative = "../../../Applications/Shipyard.app/Contents/Helpers/shipyard"
        try FileManager.default.createSymbolicLink(atPath: sandbox.link.path, withDestinationPath: relative)

        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        #expect(link.state == .linked)
        link.makeLink()

        #expect(link.state == .linked)
        #expect(try sandbox.destination() == relative)
    }

    @Test("a link to another CLI is in the way: it's kept, and the state names where it points")
    func otherLink() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeBin()
        let elsewhere = sandbox.root.appendingPathComponent("Downloads/Shipyard.app/Contents/Helpers/shipyard").path
        try FileManager.default.createSymbolicLink(atPath: sandbox.link.path, withDestinationPath: elsewhere)

        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        link.makeLink()

        #expect(link.state == .occupied(destination: elsewhere))
        #expect(try sandbox.destination() == elsewhere)
    }

    @Test("a file in the way is kept as it is")
    func fileInTheWay() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeBin()
        try Data("mine".utf8).write(to: sandbox.link)

        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        link.makeLink()

        #expect(link.state == .occupied(destination: nil))
        #expect(try String(contentsOf: sandbox.link, encoding: .utf8) == "mine")
    }

    @Test("when the link can't be made, the state carries the system's reason")
    func noPermission() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = CLILink(cli: sandbox.cli, home: sandbox.home, fileSystem: NoPermission())

        link.makeLink()

        guard case .failed(let reason) = link.state else {
            Issue.record("expected a failure, got \(link.state)")
            return
        }
        #expect(reason.contains("permission"))
        #expect(!FileManager.default.fileExists(atPath: sandbox.link.path))
    }

    @Test("without a CLI in the app there's nothing to link")
    func missingCLI() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = CLILink(cli: sandbox.root.appendingPathComponent("build/Contents/Helpers/shipyard"), home: sandbox.home)
        #expect(link.state == .missingCLI)

        link.makeLink()

        #expect(link.state == .missingCLI)
        #expect(!FileManager.default.fileExists(atPath: sandbox.link.deletingLastPathComponent().path))
    }

    @Test("a link left pointing at a CLI that's gone is in the way, with the command that fixes it")
    func brokenLink() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeBin()
        let gone = sandbox.root.appendingPathComponent("Downloads/Shipyard.app/Contents/Helpers/shipyard").path
        try FileManager.default.createSymbolicLink(atPath: sandbox.link.path, withDestinationPath: gone)

        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        link.check()

        #expect(link.state == .occupied(destination: gone))
        let text = PanelText.cliLink(link.state, command: link.command)
        #expect(text.command == link.command)
        #expect(text.action == .tryAgain)
    }

    @Test("a copy macOS runs translocated links nothing and says to move the app first")
    func translocated() throws {
        let sandbox = try Sandbox(cliPath: "private/var/folders/xy/T/AppTranslocation/0A1B2C/d/Shipyard.app")
        defer { sandbox.remove() }
        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        #expect(link.state == .translocated)

        link.makeLink()

        #expect(link.state == .translocated)
        #expect(!FileManager.default.fileExists(atPath: sandbox.link.deletingLastPathComponent().path))
        #expect(!CLILink.isTranslocated(CLILink.bundledCLI(in: URL(fileURLWithPath: "/Applications/Shipyard.app"))))
    }

    @Test("check sees a link made or removed by hand")
    func check() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        try sandbox.makeBin()
        try FileManager.default.createSymbolicLink(at: sandbox.link, withDestinationURL: sandbox.cli)

        link.check()
        #expect(link.state == .linked)

        try FileManager.default.removeItem(at: sandbox.link)
        link.check()
        #expect(link.state == .unlinked)
    }

    @Test("the command to run by hand makes the same link, replacing what's there")
    func command() throws {
        let sandbox = try Sandbox(cliPath: "My Apps/Shipyard.app")
        defer { sandbox.remove() }
        try sandbox.makeBin()
        try Data("mine".utf8).write(to: sandbox.link)
        let link = CLILink(cli: sandbox.cli, home: sandbox.home)
        #expect(link.command == "mkdir -p ~/.local/bin && ln -sf '\(sandbox.cli.path)' ~/.local/bin/shipyard")

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", link.command]
        shell.environment = ["HOME": sandbox.home.path, "PATH": "/usr/bin:/bin"]
        try shell.run()
        shell.waitUntilExit()

        #expect(shell.terminationStatus == 0)
        link.check()
        #expect(link.state == .linked)
    }

    @Test("a plain path isn't quoted in the command")
    func plainCommand() {
        let link = CLILink(
            cli: CLILink.bundledCLI(in: URL(fileURLWithPath: "/Applications/Shipyard.app")),
            home: URL(fileURLWithPath: "/Users/someone"),
            fileSystem: Empty()
        )
        #expect(link.command == "mkdir -p ~/.local/bin && ln -sf /Applications/Shipyard.app/Contents/Helpers/shipyard ~/.local/bin/shipyard")
    }
}
