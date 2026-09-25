import Foundation
@testable import ShipyardCore
import Testing

private let now = Date(timeIntervalSince1970: 1_790_337_600)

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("shipyard-state-\(UUID().uuidString)", isDirectory: true)
}

private let item = Item(
    kind: .pullRequest,
    repository: "o/r",
    number: 1,
    title: "t",
    url: URL(string: "https://github.com/o/r/pull/1")!,
    author: "a",
    authorKind: .other,
    state: .open,
    createdAt: now,
    updatedAt: now
)

@Suite("App state store")
@MainActor
struct AppStateStoreTests {
    @Test("no file is a first run; saving creates the directory and the file reads back")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        let store = AppStateStore(directory: directory)
        #expect(store.load(at: now) == .missing)
        #expect(store.state == AppState())

        store.update {
            $0.attention.markSeen(item, at: now)
            $0.collapsed.insert("shop")
        }

        let reloaded = AppStateStore(directory: directory)
        #expect(reloaded.load(at: now) == .loaded)
        #expect(reloaded.state.attention.seen[item.id]?.fingerprint == item.fingerprint)
        #expect(reloaded.state.attention.seen[item.id]?.present == now)
        #expect(reloaded.state.collapsed == ["shop"])
        #expect(store.saveError == nil)
    }

    @Test("known items, known projects and notified events read back, apart from the seen records")
    func notificationFields() throws {
        let directory = temporaryDirectory()
        let store = AppStateStore(directory: directory)
        let project = ProjectSettings(
            name: "shop", repositories: ["o/r"], pullRequests: PullRequestSettings(), issues: IssueSettings(),
            workflowRuns: WorkflowRunSettings(), notifications: []
        )
        let event = Event(kind: .prOpened, project: "shop", item: item)
        store.update {
            $0.known = KnownItems().updated(with: Snapshot(fetchedAt: now, items: ["shop": [item]]), projects: [project])
            $0.notified.insert(event, at: now)
        }

        let reloaded = AppStateStore(directory: directory)
        #expect(reloaded.load(at: now) == .loaded)
        #expect(reloaded.state == store.state)
        #expect(reloaded.state.known.items[item.id] == KnownItem(item, present: now))
        #expect(reloaded.state.known.knows(ItemSource(repository: "o/r", kind: .pullRequest), in: "shop"))
        #expect(reloaded.state.notified.contains(event))
        #expect(reloaded.state.attention.seen.isEmpty)
    }

    @Test("an update that changes nothing doesn't write")
    func noopUpdate() throws {
        let store = AppStateStore(directory: temporaryDirectory())
        store.load(at: now)

        store.update { _ in }

        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test("an unreadable file is set aside and the state starts empty", arguments: [
        "{ not json", "", "[]", #"{"seen": ["not", "a", "map"]}"#,
    ])
    func corrupt(contents: String) throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStateStore(directory: directory)
        try Data(contents.utf8).write(to: store.url)

        let result = store.load(at: now)

        let aside = directory.appendingPathComponent("state-corrupt-20260925-120000.json")
        #expect(result == .setAside(aside))
        #expect(try Data(contentsOf: aside) == Data(contents.utf8))
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        #expect(store.state == AppState())
    }

    @Test("a file with fields added later, or without some, still loads")
    func tolerant() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStateStore(directory: directory)
        // As a later version might write it: known and notified in shapes this
        // build can't read (dropped, not fatal), and a field nobody knows yet.
        let later = """
            {
              "version": 1,
              "seen": { "https://github.com/o/r/pull/1": { "fingerprint": "f", "present": "2026-09-25T12:00:00Z" } },
              "known": { "https://github.com/o/r/pull/1": {} },
              "knownProjects": ["shop"],
              "notified": ["pr.opened:https://github.com/o/r/pull/1"],
              "somethingNew": 3
            }
            """
        try Data(later.utf8).write(to: store.url)
        #expect(store.load(at: now) == .loaded)
        #expect(store.state.attention.seen["https://github.com/o/r/pull/1"]?.fingerprint == "f")
        #expect(store.state.collapsed.isEmpty)
        #expect(store.state.known == KnownItems())
        #expect(store.state.notified == NotifiedEvents())

        try Data(#"{"collapsed": ["shop"]}"#.utf8).write(to: store.url)
        #expect(store.load(at: now) == .loaded)
        #expect(store.state.collapsed == ["shop"])
        #expect(store.state.attention.seen.isEmpty)

        // A known item from before `present` was kept still loads.
        let older = """
            {
              "version": 1,
              "known": { "https://github.com/o/r/pull/1": { "repository": "o/r", "state": "open", "checks": "none",
                         "reviewRequested": false, "activity": 0, "fingerprint": "f" } }
            }
            """
        try Data(older.utf8).write(to: store.url)
        #expect(store.load(at: now) == .loaded)
        #expect(store.state.known.items["https://github.com/o/r/pull/1"]?.present == .distantPast)
    }

    @Test("a file a newer build wrote with a higher version is set aside, as a first run")
    func newerVersion() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStateStore(directory: directory)
        let newer = #"{"version": \#(AppState.currentVersion + 1), "collapsed": ["shop"]}"#
        try Data(newer.utf8).write(to: store.url)

        let result = store.load(at: now)

        let aside = directory.appendingPathComponent("state-corrupt-20260925-120000.json")
        #expect(result == .setAside(aside))
        #expect(try Data(contentsOf: aside) == Data(newer.utf8))
        #expect(store.state == AppState())

        // The current version, or none, still loads.
        try Data(#"{"version": \#(AppState.currentVersion), "collapsed": ["shop"]}"#.utf8).write(to: store.url)
        #expect(store.load(at: now) == .loaded)
        #expect(store.state.collapsed == ["shop"])
    }

    @Test("the file carries its version")
    func version() throws {
        let store = AppStateStore(directory: temporaryDirectory())
        store.update { $0.collapsed.insert("shop") }

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        #expect(json?["version"] as? Int == AppState.currentVersion)
    }
}
