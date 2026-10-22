import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

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
    version = 1
    [[projects]]
    slug = "a"
    repositories = ["o/a"]

    """

@Suite("Configuration store")
struct ConfigurationStoreTests {
    @Test("a missing file means the defaults with no projects")
    func missingFile() {
        let store = ConfigurationStore(url: temporaryConfigURL())
        #expect(store.reload() == .unchanged)
        #expect(store.lastValid == Configuration())
        #expect(store.error == nil)
    }

    @Test("a broken file keeps the last valid configuration; fixing it clears the error")
    func lastValidFallback() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)

        try write(valid, to: url)
        let first = store.reload()
        guard case .changed(let config) = first else {
            Issue.record("expected a change, got \(first)")
            return
        }
        #expect(config.projects.map(\.slug) == ["a"])
        #expect(store.lastValid == config)

        try write(valid + "[[defaults.notifications]]\nevent = \"pr.openned\"\n", to: url)
        let broken = store.reload()
        let error = try #require(store.error)
        #expect(broken == .invalid(error))
        #expect(error.line == 7)
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
        let store = ConfigurationStore(url: url)

        try write(valid, to: url)
        let first = store.reload()
        #expect(first == .changed(store.lastValid))

        try write("# a comment changes nothing\n" + valid, to: url)
        #expect(store.reload() == .unchanged)

        try write(valid + "refresh-interval = \"5m\"\n", to: url)
        #expect(store.reload() == .unchanged)
        #expect(store.warnings.map(\.message) == ["unknown setting `projects[0].refresh-interval` (ignored)"])

        try write("refresh-interval = \"5m\"\n" + valid, to: url)
        guard case .changed(let config) = store.reload() else {
            Issue.record("expected a change")
            return
        }
        #expect(config.refreshInterval == 300)
        #expect(store.warnings.isEmpty)
    }

    @Test("emptying the file goes back to no projects")
    func emptied() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        try write(valid, to: url)
        store.reload()
        try FileManager.default.removeItem(at: url)
        #expect(store.reload() == .changed(Configuration()))
        #expect(!store.lastValid.hasProjects)
    }
}

@Suite("Configuration store: appending projects")
struct ConfigurationStoreAppendTests {
    @Test("appending to a missing file creates it with a header and the schema line")
    func createsFile() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        let result = try store.append(projects: [
            NewProject(title: "e-commerce", repositories: ["o/frontend", "o/backend"]),
            NewProject(title: "blog", repositories: ["o/blog"]),
        ])

        let text = try contents(of: url)
        #expect(text.hasPrefix("#:schema \(Configuration.schemaURL)\n#"))
        #expect(text.contains("\nversion = 1\n"))
        #expect(text.hasSuffix("""

            [[projects]]
            slug = "e-commerce"
            repositories = ["o/frontend", "o/backend"]

            [[projects]]
            slug = "blog"
            repositories = ["o/blog"]

            """))
        guard case .changed(let config) = result else {
            Issue.record("expected a change, got \(result)")
            return
        }
        #expect(config.projects.map(\.slug) == ["e-commerce", "blog"])
        #expect(config.projects[0].repositories == ["o/frontend", "o/backend"])
        #expect(store.warnings.isEmpty)
    }

    @Test("appending keeps the existing text and comments untouched")
    func keepsExistingText() throws {
        let url = temporaryConfigURL()
        let existing = """
            # hand-written, keep me
            refresh-interval = "60s"   # quick

            [[projects]]
            slug = "a"   # the first one
            repositories = ["o/a"]
            """
        try write(existing, to: url)
        let store = ConfigurationStore(url: url)
        store.reload()

        try store.append(projects: [NewProject(title: "b", repositories: ["o/b"])])

        let text = try contents(of: url)
        #expect(text.hasPrefix(existing + "\n"))
        #expect(text == existing + "\n\n[[projects]]\nslug = \"b\"\nrepositories = [\"o/b\"]\n")
        #expect(store.lastValid.projects.map(\.slug) == ["a", "b"])
        #expect(store.lastValid.refreshInterval == 60)
    }

    @Test("appending escapes names so they read back the same")
    func escapes() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        let name = "quotes \" and \\ backslash"
        try store.append(projects: [NewProject(title: name, repositories: ["o/a"])])
        #expect(store.lastValid.projects.map(\.title) == [name])
    }

    @Test("appending rejects bad slugs, names already used and a repository listed twice, without writing")
    func rejects() throws {
        let url = temporaryConfigURL()
        try write(valid, to: url)
        let store = ConfigurationStore(url: url)
        store.reload()

        #expect(throws: ConfigurationError([ConfigurationIssue(line: nil, message: "repository `nope` isn't `owner/name`")])) {
            try store.append(projects: [NewProject(title: "b", repositories: ["nope"])])
        }
        #expect(throws: ConfigurationError([ConfigurationIssue(line: nil, message: "project slug `a` is already used")])) {
            try store.append(projects: [NewProject(title: "A", repositories: ["o/b"])])
        }
        #expect(throws: ConfigurationError([ConfigurationIssue(line: nil, message: "project `!!` needs a letter or digit in its name, for its slug")])) {
            try store.append(projects: [NewProject(title: "!!", repositories: ["o/b"])])
        }
        #expect(throws: ConfigurationError([ConfigurationIssue(line: nil, message: "project `b` lists repository `O/B` twice (names aren't case-sensitive)")])) {
            try store.append(projects: [NewProject(title: "b", repositories: ["o/b", "O/B"])])
        }
        #expect(try contents(of: url) == valid)
    }
}

@Suite("Configuration store: setting the layout")
struct ConfigurationStoreLayoutTests {
    private func setLayout(_ layout: MenuLayout, in text: String) throws -> (text: String, store: ConfigurationStore) {
        let url = temporaryConfigURL()
        try write(text, to: url)
        let store = ConfigurationStore(url: url)
        store.reload()
        try store.setLayout(layout)
        return (try contents(of: url), store)
    }

    @Test("an existing layout's value is replaced, keeping its comment and every other line")
    func replacesValue() throws {
        let before = """
            # mine
            refresh-interval = "60s"

            [menu]   # how it looks
            layout = "list"   # or tabs

            [[projects]]
            slug = "a"
            repositories = ["o/a"]

            """
        let (after, store) = try setLayout(.tabs, in: before)
        #expect(after == before.replacingOccurrences(of: "layout = \"list\"", with: "layout = \"tabs\""))
        #expect(store.lastValid.menu.layout == .tabs)
        #expect(store.lastValid.refreshInterval == 60)
        #expect(store.lastValid.projects.map(\.slug) == ["a"])
    }

    @Test("a [menu] table without the key gets it under its header")
    func addsKeyToTable() throws {
        let before = "[menu]\n\n[[projects]]\nslug = \"a\"\nrepositories = [\"o/a\"]\n"
        let (after, store) = try setLayout(.tabs, in: before)
        #expect(after == "[menu]\nlayout = \"tabs\"\n\n[[projects]]\nslug = \"a\"\nrepositories = [\"o/a\"]\n")
        #expect(store.lastValid.menu.layout == .tabs)
    }

    @Test("the new-file header's commented [menu] example is uncommented in place, its projects kept")
    func uncommentsHeaderExample() throws {
        let projects = "\n[[projects]]\nslug = \"a\"\nrepositories = [\"o/a\"]\n"
        let before = Configuration.header + projects
        let (after, store) = try setLayout(.tabs, in: before)
        let expected = Configuration.header
            .replacingOccurrences(of: "# [menu]\n# layout = \"list\"\n", with: "[menu]\nlayout = \"tabs\"\n") + projects
        #expect(after == expected)
        #expect(after != before)
        #expect(store.lastValid.menu.layout == .tabs)
        #expect(store.lastValid.projects.map(\.slug) == ["a"])
        #expect(store.warnings.isEmpty)

        try store.setLayout(.list)
        #expect(try contents(of: store.url) == expected.replacingOccurrences(of: "layout = \"tabs\"", with: "layout = \"list\""))
        #expect(store.lastValid.menu.layout == .list)
    }

    @Test("a commented [menu] followed by live settings isn't uncommented: a new table goes before the first table")
    func commentedMenuOverLiveKeys() throws {
        let before = """
            # [menu]
            # layout = "list"
            refresh-interval = "60s"

            # my projects
            [[projects]]
            slug = "a"
            repositories = ["o/a"]

            """
        let (after, store) = try setLayout(.tabs, in: before)
        #expect(after == """
            # [menu]
            # layout = "list"
            refresh-interval = "60s"

            [menu]
            layout = "tabs"

            # my projects
            [[projects]]
            slug = "a"
            repositories = ["o/a"]

            """)
        #expect(store.lastValid.menu.layout == .tabs)
        #expect(store.lastValid.refreshInterval == 60)
    }

    @Test("a file without [menu] gets one before its first table")
    func addsTable() throws {
        let before = """
            #:schema \(Configuration.schemaURL)
            version = 1
            launch-at-login = false

            [menu-bar]
            count = "none"

            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            """
        let (after, store) = try setLayout(.tabs, in: before)
        #expect(after == """
            #:schema \(Configuration.schemaURL)
            version = 1
            launch-at-login = false

            [menu]
            layout = "tabs"

            [menu-bar]
            count = "none"

            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            """)
        #expect(store.lastValid.menu.layout == .tabs)
        #expect(store.lastValid.menuBar.count == .none)
        #expect(store.lastValid.launchAtLogin == false)
    }

    @Test("a file with no tables gets [menu] at the end")
    func addsTableAtEnd() throws {
        let (after, store) = try setLayout(.tabs, in: "version = 1")
        #expect(after == "version = 1\n\n[menu]\nlayout = \"tabs\"\n")
        #expect(store.lastValid.menu.layout == .tabs)

        let (fromEmpty, _) = try setLayout(.tabs, in: "")
        #expect(fromEmpty == "[menu]\nlayout = \"tabs\"\n")
    }

    @Test("a missing file is created with its header, whose example is uncommented")
    func missingFile() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        try store.setLayout(.tabs)
        #expect(try contents(of: url) == Configuration.header
            .replacingOccurrences(of: "# [menu]\n# layout = \"list\"\n", with: "[menu]\nlayout = \"tabs\"\n"))
        #expect(store.lastValid.menu.layout == .tabs)
    }

    @Test("a broken file isn't written: its own error says why")
    func brokenFile() throws {
        let url = temporaryConfigURL()
        let broken = "[menu]\nlayout = \"list\"\n\n[[projects]]\nslug = \"a\"\nrepositories = [\"nope\"]\n"
        try write(broken, to: url)
        let store = ConfigurationStore(url: url)
        #expect(throws: ConfigurationError([ConfigurationIssue(line: 6, message: "unknown repository group `nope` (did you mean `nope/*`, or a repository as `nope/name`?)")])) {
            try store.setLayout(.tabs)
        }
        #expect(try contents(of: url) == broken)
    }

    @Test("a [menu] written as an inline table isn't edited, and says how to set it by hand")
    func inlineTable() throws {
        let url = temporaryConfigURL()
        let inline = "menu = { layout = \"list\" }\n"
        try write(inline, to: url)
        let store = ConfigurationStore(url: url)
        store.reload()
        #expect(throws: ConfigurationError([ConfigurationIssue(
            line: 1,
            message: "can't switch the layout: `[menu]` is written in a form shipyard doesn't edit; set `layout = \"tabs\"` under `[menu]` by hand"
        )])) {
            try store.setLayout(.tabs)
        }
        #expect(try contents(of: url) == inline)
        #expect(store.lastValid.menu.layout == .list)
    }
}

@Suite("Configuration store: setting the theme")
struct ConfigurationStoreThemeTests {
    /// One write of the Theme submenu: the file before, the name picked, the file after.
    struct Case: CustomTestStringConvertible, Sendable {
        var name: String
        var before: String
        var pick: String
        var after: String
        var testDescription: String { name }
    }

    static let projects = "\n[[projects]]\nslug = \"a\"\nrepositories = [\"o/a\"]\n"

    static let cases: [Case] = [
        Case(name: "an existing theme's value is replaced, keeping its comment, the theme's spelling and every other line", before: """
            # mine
            version = 1
            theme = "Ocean"   # the dark one
            refresh-interval = "60s"

            [menu]
            layout = "list"
            \(projects)
            """, pick: "paper light", after: """
            # mine
            version = 1
            theme = "Paper Light"   # the dark one
            refresh-interval = "60s"

            [menu]
            layout = "list"
            \(projects)
            """),
        Case(name: "the new-file header's commented example is uncommented in place", before: Configuration.header + projects, pick: "Harbor",
             after: Configuration.header.replacingOccurrences(of: "# theme = \"System\"\n", with: "theme = \"Harbor\"\n") + projects),
        Case(name: "a file without the key gets it after version, above every table", before: """
            #:schema \(Configuration.schemaURL)
            version = 1
            launch-at-login = false

            [menu]
            layout = "tabs"
            """, pick: "Sunset", after: """
            #:schema \(Configuration.schemaURL)
            version = 1
            theme = "Sunset"
            launch-at-login = false

            [menu]
            layout = "tabs"
            """),
        Case(name: "a file without version gets it above its first table and that table's comment", before: """
            refresh-interval = "60s"

            # my projects
            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            """, pick: "System", after: """
            refresh-interval = "60s"

            theme = "System"

            # my projects
            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            """),
        Case(name: "an empty file gets the key alone", before: "", pick: "Brass", after: "theme = \"Brass\"\n"),
    ]

    @Test("the Theme submenu's write changes only the top-level theme, keeping comments and order", arguments: cases)
    func setsTheme(_ example: Case) throws {
        let url = temporaryConfigURL()
        try write(example.before, to: url)
        let store = ConfigurationStore(url: url)
        store.reload()
        let before = store.lastValid
        try store.setTheme(example.pick)
        #expect(try contents(of: url) == example.after)
        var expected = before
        expected.theme = try #require(store.themes.theme(named: example.pick)).name
        #expect(store.error == nil)
        #expect(store.lastValid == expected)
        #expect(store.theme.name == expected.theme)
    }

    @Test("a missing file is created with its header, whose example is uncommented")
    func missingFile() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        try store.setTheme("Shipyard Dark")
        #expect(try contents(of: url) == Configuration.header
            .replacingOccurrences(of: "# theme = \"System\"\n", with: "theme = \"Shipyard Dark\"\n"))
        #expect(store.theme.name == "Shipyard Dark")
    }

    @Test("a file that doesn't read, a name that's no theme and a theme written in a form shipyard doesn't edit leave the file as it was, with the reason")
    func refused() throws {
        let url = temporaryConfigURL()
        let broken = "version = 1\ntheme = \"Ocean\"\n\n[[projects]]\nslug = \"a\"\nrepositories = [\"nope\"]\n"
        try write(broken, to: url)
        let store = ConfigurationStore(url: url)
        #expect(throws: ConfigurationError([ConfigurationIssue(line: 6, message: "unknown repository group `nope` (did you mean `nope/*`, or a repository as `nope/name`?)")])) {
            try store.setTheme("Brass")
        }
        #expect(try contents(of: url) == broken)

        let valid = "version = 1\ntheme = \"Ocean\"\n"
        try write(valid, to: url)
        store.reload()
        #expect(throws: ConfigurationError.self) { try store.setTheme("Midnight") }
        #expect(try contents(of: url) == valid)

        let multiline = "version = 1\ntheme = \"\"\"Ocean\"\"\"\n"
        try write(multiline, to: url)
        store.reload()
        #expect(throws: ConfigurationError([ConfigurationIssue(
            line: 2,
            message: "can't switch the theme: `theme` is written in a form shipyard doesn't edit; set `theme = \"Brass\"` at the top of the file by hand"
        )])) {
            try store.setTheme("Brass")
        }
        #expect(try contents(of: url) == multiline)
        #expect(store.theme.name == "Ocean")
    }

    @Test("a theme picked before onboarding's preset stays in the preset's file")
    func presetKeepsTheme() throws {
        let url = temporaryConfigURL()
        let store = ConfigurationStore(url: url)
        try store.createIfMissing()
        try store.setTheme("Heather")
        #expect(store.acceptsPreset)
        try store.writePreset(.reviewQueue)
        #expect(store.error == nil)
        #expect(store.theme.name == "Heather")
        #expect(store.lastValid.theme == "Heather")
        #expect(try contents(of: url).contains("theme = \"Heather\""))
    }
}

@Suite("Configuration store: location")
struct ConfigurationStoreLocationTests {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test("the file is under XDG_CONFIG_HOME when it's set")
    func xdg() {
        let url = ConfigurationStore.defaultURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home)
        #expect(url.path == "/tmp/xdg/shipyard/config.toml")
    }

    @Test("the file is under ~/.config otherwise")
    func fallback() {
        for environment in [[:], ["XDG_CONFIG_HOME": ""], ["XDG_CONFIG_HOME": "relative/path"]] {
            let url = ConfigurationStore.defaultURL(environment: environment, home: home)
            #expect(url.path == "/Users/someone/.config/shipyard/config.toml")
        }
    }
}
