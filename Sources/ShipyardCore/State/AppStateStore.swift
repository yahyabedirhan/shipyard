import Foundation

/// What shipyard remembers on its own from how the user uses it. Never
/// written to the configuration.
public struct AppState: Equatable, Sendable {
    /// The version of the file format this build writes. Adding a field is
    /// not a new version: every field is optional when read, so an older
    /// file loads with the new field empty and a newer file's extra fields
    /// are ignored. Bump it only for a change an older reader would
    /// misunderstand, with a migration in `init(from:)`.
    public static let currentVersion = 1

    /// Which version of each item the user has seen.
    public var attention = Attention()
    /// Projects whose sections are collapsed, by name.
    public var collapsed: Set<String> = []
    /// What the refreshes so far found, for finding events: each item's last
    /// version and the sources each project was fetched from.
    public var known = KnownItems()
    /// Events already notified or passed over, so none is notified twice.
    /// Kept apart from `attention`: seeing an item says nothing about its events.
    public var notified = NotifiedEvents()

    public init(
        attention: Attention = Attention(),
        collapsed: Set<String> = [],
        known: KnownItems = KnownItems(),
        notified: NotifiedEvents = NotifiedEvents()
    ) {
        self.attention = attention
        self.collapsed = collapsed
        self.known = known
        self.notified = notified
    }
}

// `state.json`:
//
//     {
//       "version": 1,
//       "seen": { "<item url>": { "fingerprint": "…", "present": "2026-09-25T12:00:00Z" } },
//       "collapsed": ["job-search"],
//       "known": { "<item url>": { "repository": "o/r", "state": "open", "checks": "pending",
//                                  "reviewRequested": false, "activity": 0, "fingerprint": "…" } },
//       "knownProjects": { "job-search": [{ "repository": "o/r", "kind": "pullRequest" }] },
//       "notified": { "<item url>": { "events": ["pr.opened"], "present": "2026-09-25T12:00:00Z" } }
//     }
//
// `known`, `knownProjects` and `notified` came with notification rules (#8).
// Each is optional, and one that can't be read is dropped rather than making
// the whole file unreadable: without them the next refresh is silent (no
// project is known), which is the safe way to fail. Inside them, an entry a
// newer build wrote that this one can't read (a new state, say) is skipped.
extension AppState: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case seen
        case collapsed
        case known
        case knownProjects
        case notified
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .version)
        let seen = try container.decodeIfPresent([String: Attention.SeenRecord].self, forKey: .seen) ?? [:]
        attention = Attention(seen: seen)
        collapsed = try container.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? []
        let items = (try? container.decodeIfPresent([String: Lossy<KnownItem>].self, forKey: .known)) ?? [:]
        let sources = (try? container.decodeIfPresent([String: [Lossy<ItemSource>]].self, forKey: .knownProjects)) ?? [:]
        known = KnownItems(
            items: items.compactMapValues(\.value),
            sources: sources.mapValues { Set($0.compactMap(\.value)) }
        )
        let records = (try? container.decodeIfPresent([String: Lossy<NotifiedEvents.Record>].self, forKey: .notified)) ?? [:]
        notified = NotifiedEvents(records: records.compactMapValues(\.value))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(attention.seen, forKey: .seen)
        try container.encode(collapsed.sorted(), forKey: .collapsed)
        try container.encode(known.items, forKey: .known)
        try container.encode(known.sources.mapValues { $0.sorted() }, forKey: .knownProjects)
        try container.encode(notified.records, forKey: .notified)
    }
}

/// Decodes a value, or `nil` when it can't, so one unreadable entry doesn't
/// fail the collection around it.
private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Keeps `AppState` in one JSON file, `state.json`, in a directory the app
/// provides (`~/Library/Application Support/Shipyard/`). The file is
/// app-owned and never hand-edited.
///
/// `load` reads it once at start. A file that can't be read as app state is
/// renamed aside (`state-corrupt-<time>.json`) and shipyard starts as on a
/// first run. `update` changes the state and saves it when it changed.
@MainActor
public final class AppStateStore {
    /// What `load` found.
    public enum LoadResult: Equatable, Sendable {
        /// No file yet: a first run.
        case missing
        case loaded
        /// The file was unreadable; it was moved to this URL and the state
        /// starts empty.
        case setAside(URL)
    }

    public static let fileName = "state.json"

    /// The directory the app provides.
    public let directory: URL
    /// `state.json` in `directory`.
    public var url: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// The state as last loaded or updated.
    public private(set) var state = AppState()
    /// Why the latest save failed; `nil` once one succeeds.
    public private(set) var saveError: String?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads `state.json`. A missing file is a first run; an unreadable one
    /// is set aside and treated as a first run.
    @discardableResult
    public func load(at now: Date = Date()) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            state = AppState()
            return .missing
        }
        do {
            state = try Self.decoder.decode(AppState.self, from: data)
            return .loaded
        } catch {
            state = AppState()
            return .setAside(setAside(at: now))
        }
    }

    /// Changes the state with `body` and saves it when it changed.
    public func update(_ body: (inout AppState) -> Void) {
        var next = state
        body(&next)
        guard next != state else { return }
        state = next
        save()
    }

    /// Writes the state, replacing the file atomically.
    public func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Moves the unreadable file out of the way, keeping it for a look later.
    private func setAside(at now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let target = directory.appendingPathComponent("state-corrupt-\(formatter.string(from: now)).json", isDirectory: false)
        try? FileManager.default.removeItem(at: target)
        if (try? FileManager.default.moveItem(at: url, to: target)) == nil {
            // Can't move it: drop it, so the next save isn't blocked by it.
            try? FileManager.default.removeItem(at: url)
        }
        return target
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
