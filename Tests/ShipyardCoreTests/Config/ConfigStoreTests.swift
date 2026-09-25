import Foundation
@testable import ShipyardCore
import Testing

/// A fresh configuration directory under the system's temporary directory.
private func temporaryConfigURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("shipyard", isDirectory: true)
        .appendingPathComponent("config.toml")
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

private let valid = """
    # my projects
    [[projects]]
    name = "a"
    repositories = ["o/a"]

    """

@Suite("Configuration store")
struct ConfigStoreTests {
    @Test("a missing file means the defaults with no projects")
    func missingFile() {
        let store = ConfigStore(url: temporaryConfigURL())
        #expect(store.reload() == .unchanged)
        #expect(store.lastValid == Configuration())
        #expect(store.error == nil)
    }

    @Test("an empty file means the defaults with no projects")
    func emptyFile() throws {
        let url = temporaryConfigURL()
        try write("", to: url)
        let store = ConfigStore(url: url)
        store.reload()
        #expect(store.lastValid.projects.isEmpty)
        #expect(store.error == nil)
    }

    @Test("a broken file keeps the last valid configuration; fixing it clears the error")
    func lastValidFallback() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)

        try write(valid, to: url)
        let first = store.reload()
        guard case .changed(let config) = first else {
            Issue.record("expected a change, got \(first)")
            return
        }
        #expect(config.projects.map(\.name) == ["a"])
        #expect(store.lastValid == config)

        try write(valid + "[[defaults.notifications]]\nevent = \"pr.openned\"\n", to: url)
        let broken = store.reload()
        let error = try #require(store.error)
        #expect(broken == .invalid(error))
        #expect(error.line == 6)
        #expect(error.message == "unknown event `pr.openned` (did you mean `pr.opened`?)")
        #expect(store.lastValid == config)

        try write(valid, to: url)
        #expect(store.reload() == .changed(config))
        #expect(store.error == nil)
        #expect(store.lastValid == config)
    }

    @Test("a reload that means the same as before is unchanged")
    func unchangedReload() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)

        try write(valid, to: url)
        let first = store.reload()
        #expect(first == .changed(store.lastValid))

        try write("# a comment changes nothing\n" + valid, to: url)
        #expect(store.reload() == .unchanged)

        try write(valid + "refresh-interval-seconds = 300\n", to: url)
        // A top-level key after a table belongs to that table: an unknown key, so still unchanged.
        #expect(store.reload() == .unchanged)
        #expect(store.warnings.map(\.message) == ["unknown key `projects[0].refresh-interval-seconds` is ignored"])

        try write("refresh-interval-seconds = 300\n" + valid, to: url)
        guard case .changed(let config) = store.reload() else {
            Issue.record("expected a change")
            return
        }
        #expect(config.refreshIntervalSeconds == 300)
        #expect(store.warnings.isEmpty)
    }

    @Test("emptying the file goes back to no projects")
    func emptied() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)
        try write(valid, to: url)
        store.reload()
        try FileManager.default.removeItem(at: url)
        #expect(store.reload() == .changed(Configuration()))
        #expect(!store.lastValid.hasProjects)
    }
}

@Suite("Configuration store: creating the file")
struct ConfigStoreCreateTests {
    @Test("a missing file is created with the header alone, and reads as no projects")
    func createsMissing() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)

        let created = try store.createIfMissing()

        #expect(created)
        #expect(try contents(of: url) == Configuration.header)
        #expect(store.reload() == .unchanged)
        #expect(store.error == nil)
    }

    @Test("an existing file is left untouched")
    func keepsExisting() throws {
        let url = temporaryConfigURL()
        try write(valid, to: url)
        let store = ConfigStore(url: url)

        let created = try store.createIfMissing()

        #expect(!created)
        #expect(try contents(of: url) == valid)
    }
}

@Suite("Configuration store: appending projects")
struct ConfigStoreAppendTests {
    @Test("appending to a missing file creates it with a header and the schema line")
    func createsFile() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)
        let result = try store.append(projects: [
            NewProject(name: "e-commerce", repositories: ["o/frontend", "o/backend"]),
            NewProject(name: "blog", repositories: ["o/blog"]),
        ])

        let text = try contents(of: url)
        #expect(text.hasPrefix("#:schema \(Configuration.schemaURL)\n#"))
        #expect(text.contains("\nversion = 1\n"))
        #expect(text.hasSuffix("""

            [[projects]]
            name = "e-commerce"
            repositories = ["o/frontend", "o/backend"]

            [[projects]]
            name = "blog"
            repositories = ["o/blog"]

            """))
        guard case .changed(let config) = result else {
            Issue.record("expected a change, got \(result)")
            return
        }
        #expect(config.projects.map(\.name) == ["e-commerce", "blog"])
        #expect(config.projects[0].repositories == ["o/frontend", "o/backend"])
        #expect(store.warnings.isEmpty)
    }

    @Test("appending keeps the existing text and comments untouched")
    func keepsExistingText() throws {
        let url = temporaryConfigURL()
        let existing = """
            # hand-written, keep me
            refresh-interval-seconds = 60   # quick

            [[projects]]
            name = "a"   # the first one
            repositories = ["o/a"]
            """ // no trailing newline
        try write(existing, to: url)
        let store = ConfigStore(url: url)
        store.reload()

        try store.append(projects: [NewProject(name: "b", repositories: ["o/b"])])

        let text = try contents(of: url)
        #expect(text.hasPrefix(existing + "\n"))
        #expect(text == existing + "\n\n[[projects]]\nname = \"b\"\nrepositories = [\"o/b\"]\n")
        #expect(store.lastValid.projects.map(\.name) == ["a", "b"])
        #expect(store.lastValid.refreshIntervalSeconds == 60)
    }

    @Test("appending escapes names so they read back the same")
    func escapes() throws {
        let url = temporaryConfigURL()
        let store = ConfigStore(url: url)
        let name = "quotes \" and \\ backslash"
        try store.append(projects: [NewProject(name: name, repositories: ["o/a"])])
        #expect(store.lastValid.projects.map(\.name) == [name])
    }

    @Test("appending rejects bad slugs, names already used and a repository listed twice, without writing")
    func rejects() throws {
        let url = temporaryConfigURL()
        try write(valid, to: url)
        let store = ConfigStore(url: url)
        store.reload()

        #expect(throws: ConfigError([ConfigIssue(line: nil, message: "repository `nope` isn't `owner/name`")])) {
            try store.append(projects: [NewProject(name: "b", repositories: ["nope"])])
        }
        #expect(throws: ConfigError([ConfigIssue(line: nil, message: "project name `a` is already used")])) {
            try store.append(projects: [NewProject(name: "a", repositories: ["o/b"])])
        }
        #expect(throws: ConfigError([ConfigIssue(line: nil, message: "project `b` lists repository `O/B` twice (names aren't case-sensitive)")])) {
            try store.append(projects: [NewProject(name: "b", repositories: ["o/b", "O/B"])])
        }
        #expect(try contents(of: url) == valid)
    }
}

@Suite("Configuration store: location")
struct ConfigStoreLocationTests {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test("the file is under XDG_CONFIG_HOME when it's set")
    func xdg() {
        let url = ConfigStore.defaultURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home)
        #expect(url.path == "/tmp/xdg/shipyard/config.toml")
    }

    @Test("the file is under ~/.config otherwise")
    func fallback() {
        for environment in [[:], ["XDG_CONFIG_HOME": ""], ["XDG_CONFIG_HOME": "relative/path"]] {
            let url = ConfigStore.defaultURL(environment: environment, home: home)
            #expect(url.path == "/Users/someone/.config/shipyard/config.toml")
        }
    }
}
