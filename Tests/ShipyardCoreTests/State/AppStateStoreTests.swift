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
        // As a later version might write it: the fields #8 adds, and one nobody knows yet.
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

        try Data(#"{"collapsed": ["shop"]}"#.utf8).write(to: store.url)
        #expect(store.load(at: now) == .loaded)
        #expect(store.state.collapsed == ["shop"])
        #expect(store.state.attention.seen.isEmpty)
    }

    @Test("the file carries its version")
    func version() throws {
        let store = AppStateStore(directory: temporaryDirectory())
        store.update { $0.collapsed.insert("shop") }

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        #expect(json?["version"] as? Int == AppState.currentVersion)
    }
}
