import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// What `ntn api` was asked, and answers with.
private final class FakeNtn: Sendable {
    private let calls = Locked<[(executable: String, arguments: [String])]>([])
    private let answer: NtnCLI.Output?

    init(_ answer: NtnCLI.Output?) { self.answer = answer }

    var run: NtnCLI.Run {
        { executable, arguments in
            self.calls.withValue { $0.append((executable, arguments)) }
            return self.answer
        }
    }

    var arguments: [[String]] { calls.current.map(\.arguments) }
    var executables: [String] { calls.current.map(\.executable) }
}

private func ntn(_ fake: FakeNtn, installed: Set<String> = ["/home/me/.local/bin/ntn"]) -> NtnCLI {
    NtnCLI(home: "/home/me", isExecutable: { installed.contains($0) }, pathEnvironment: nil, run: fake.run)
}

private func output(_ status: Int32, out: String = "", err: String = "") -> NtnCLI.Output {
    NtnCLI.Output(status: status, standardOutput: Data(out.utf8), standardError: err)
}

/// The notes read Notion through `ntn api`, Notion's CLI, as the HTTP
/// transport `NotionClient` sends through: each request becomes one run,
/// and the run's exit code and error line become the status Notion gave.
@Suite("ntn as the notes' transport")
struct NtnCLITests {
    @Test("a request runs ntn api with its path, query, method, version and JSON body")
    func arguments() async throws {
        let fake = FakeNtn(output(0, out: #"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        let client = NotionClient(transport: ntn(fake))

        _ = try await client.childPages(of: "page-1")
        _ = try await client.searchPages(titled: "Shipyard Notes")

        #expect(fake.executables == ["/home/me/.local/bin/ntn", "/home/me/.local/bin/ntn"])
        let children = try #require(fake.arguments.first)
        #expect(children == ["api", "v1/blocks/page-1/children", "page_size==100", "-X", "GET", "--notion-version", NotionClient.version])
        let search = try #require(fake.arguments.last)
        #expect(Array(search.prefix(6)) == ["api", "v1/search", "-X", "POST", "--notion-version", NotionClient.version])
        #expect(search[6] == "-d")
        let body = try JSONSerialization.jsonObject(with: Data(search[7].utf8)) as? [String: Any]
        #expect(body?["query"] as? String == "Shipyard Notes")
    }

    @Test(
        "ntn's exit and error line come back as Notion's status",
        arguments: [
            // Logged out, no workspace, or a token Notion stopped taking: exit 4.
            (output(4, err: "error: No workspace selected.\n  hint: Run `ntn login` first"), NotionError.unauthorized),
            (output(4, err: "error: Public API request failed: API token is invalid."), NotionError.unauthorized),
            // An API error: exit 5, with the status and Notion's code in the line.
            (
                output(5, err: "error: Public API request failed (404 Not Found object_not_found): Could not find page with ID: x."),
                NotionError.http(404, code: "object_not_found", message: "Could not find page with ID: x.")
            ),
            (output(5, err: "error: Public API request failed (429 Too Many Requests rate_limited): slow down"), NotionError.rateLimited(retryAfter: nil)),
            // Anything else is the run's own failure, in its first line.
            (output(1, err: "error: connection refused\nmore"), NotionError.network("ntn: error: connection refused")),
        ]
    )
    func failures(answer: NtnCLI.Output, expected: NotionError) async {
        let client = NotionClient(transport: ntn(FakeNtn(answer)))
        await #expect(throws: expected) { try await client.me() }
    }

    @Test("no ntn anywhere is its own error, and nothing runs")
    func missing() async {
        let fake = FakeNtn(output(0, out: "{}"))
        let client = NotionClient(transport: ntn(fake, installed: []))
        await #expect(throws: NotionError.ntnMissing) { try await client.me() }
        #expect(fake.arguments.isEmpty)

        let unstartable = NotionClient(transport: ntn(FakeNtn(nil)))
        await #expect(throws: NotionError.ntnMissing) { try await unstartable.me() }
    }

    @Test("ntn is looked for where its installer puts it, then Homebrew's paths, then PATH")
    func locate() {
        let home = "/home/me"
        #expect(NtnCLI.locate(home: home, isExecutable: { _ in true }, pathEnvironment: "/bin") == "/home/me/.local/bin/ntn")
        #expect(NtnCLI.locate(home: home, isExecutable: { $0 == "/opt/homebrew/bin/ntn" || $0 == "/bin/ntn" }, pathEnvironment: "/bin") == "/opt/homebrew/bin/ntn")
        #expect(NtnCLI.locate(home: home, isExecutable: { $0 == "/b/ntn" }, pathEnvironment: "/a:/b/") == "/b/ntn")
        #expect(NtnCLI.locate(home: home, isExecutable: { _ in false }, pathEnvironment: "/a") == nil)
    }
}
