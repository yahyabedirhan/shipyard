import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

/// The main test seam: a real `Shipyard` driven end to end over in-memory
/// ports. The network is `StubHTTP` answering from recorded GitHub
/// responses (`Fixtures/`); the configuration lives in a temporary
/// directory; the clock, the refresh timer and waiting are manual; the URL
/// opener and notifier record what they're asked.
///
/// A scenario writes a configuration, registers answers, drives the
/// orchestrator (`start`, `timer.fire()`, `reloadConfiguration`, clicks) and
/// asserts on `shipyard.menu` and what the ports recorded.
@MainActor
struct Harness {
    /// 2026-09-25 12:00:00 UTC, the "now" the fixtures are written against.
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_337_600)
    /// `x-ratelimit-reset` the fixtures' headers carry: 12:42 the same day.
    nonisolated static let rateLimitReset = Date(timeIntervalSince1970: 1_790_340_120)

    nonisolated static let userURL = GitHubClient.apiURL.appendingPathComponent("user")
    nonisolated static let viewerAnswer = StubHTTP.Answer.json(#"{"login":"yabepa","id":42,"type":"User"}"#)
    nonisolated static let unauthorized = StubHTTP.Answer.json(
        #"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}"#, status: 401
    )

    let stub = StubHTTP()
    let store: InMemoryTokenStore
    let gh: FakeGhLookup
    let sleeper = InstantSleeper(clock: ManualClock(Harness.now))
    let timer = ManualTimer()
    let opener = RecordingURLOpener()
    /// Not wired yet: notifications arrive with the notification rules.
    let notifier = RecordingNotifier()
    /// `config.toml` in a fresh temporary directory.
    let configURL: URL
    /// A fresh temporary directory for app state, for the app-state store.
    let stateDirectory: URL
    let shipyard: Shipyard

    var clock: ManualClock { sleeper.clock }

    /// A harness with the given token store and `gh` tokens and, when
    /// `config` isn't `nil`, that configuration file.
    init(stored: String? = nil, gh ghToken: String? = nil, config: String? = nil) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-tests-\(UUID().uuidString)", isDirectory: true)
        configURL = root.appendingPathComponent("config", isDirectory: true).appendingPathComponent("config.toml")
        stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        if let config { try Data(config.utf8).write(to: configURL) }

        store = InMemoryTokenStore(token: stored)
        gh = FakeGhLookup(token: ghToken)
        shipyard = Shipyard(
            configStore: ConfigStore(url: configURL),
            tokenStore: store,
            urlOpener: opener,
            gh: gh,
            transport: stub,
            clock: sleeper.clock,
            timer: timer,
            sleep: sleeper.sleep,
            oauthClientID: "test-client-id"
        )
    }

    /// A harness signed in with a stored token, with `config` on disk and
    /// GraphQL answering `answers` in order, after `start()` (which runs the
    /// first refresh when there are projects).
    static func started(config: String, graphQL answers: StubHTTP.Answer...) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(userURL, viewerAnswer)
        if !answers.isEmpty { harness.graphQL(answers) }
        await harness.shipyard.start()
        return harness
    }

    /// A recorded GraphQL answer from `Fixtures/`, with GitHub's rate-limit headers.
    nonisolated static func fixture(
        _ name: String,
        status: Int = 200,
        remaining: Int = 4990,
        reset: Date = rateLimitReset
    ) throws -> StubHTTP.Answer {
        try .fixture(name, status: status, headers: rateLimitHeaders(remaining: remaining, reset: reset))
    }

    /// The `x-ratelimit-*` headers of a GraphQL response (or, with
    /// `resource: "core"`, a REST one).
    nonisolated static func rateLimitHeaders(
        remaining: Int,
        reset: Date = rateLimitReset,
        resource: String = "graphql"
    ) -> [String: String] {
        [
            "x-ratelimit-limit": "5000",
            "x-ratelimit-remaining": String(remaining),
            "x-ratelimit-used": String(5000 - remaining),
            "x-ratelimit-reset": String(Int(reset.timeIntervalSince1970)),
            "x-ratelimit-resource": resource,
        ]
    }

    /// Answers `POST /graphql` with `answers` in order, the last repeating.
    func graphQL(_ answers: [StubHTTP.Answer]) {
        stub.on("POST", GitHubClient.graphQLURL, answers: answers)
    }

    /// Every GraphQL request sent.
    var graphQLRequests: [URLRequest] { stub.requests("POST", GitHubClient.graphQLURL) }

    /// The `Authorization` header of every `GET /user`.
    var authorizations: [String?] {
        stub.requests("GET", Self.userURL).map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    /// Replaces the configuration file with `text`.
    func writeConfig(_ text: String) throws {
        try Data(text.utf8).write(to: configURL)
    }

    /// The section named `name` in the current menu.
    func section(_ name: String) -> MenuSection? {
        shipyard.menu.sections.first { $0.name == name }
    }
}

/// An ISO 8601 date, for comparing with the fixtures.
func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
