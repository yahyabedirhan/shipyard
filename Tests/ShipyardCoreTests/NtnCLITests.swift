import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

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
            (output(4, err: "error: No workspace selected.\n  hint: Run `ntn login` first"), NotionError.unauthorized),
            (output(4, err: "error: Public API request failed: API token is invalid."), NotionError.unauthorized),
            (
                output(5, err: "error: Public API request failed (404 Not Found object_not_found): Could not find page with ID: x."),
                NotionError.http(404, code: "object_not_found", message: "Could not find page with ID: x.")
            ),
            (output(5, err: "error: Public API request failed (429 Too Many Requests rate_limited): slow down"), NotionError.rateLimited(retryAfter: nil)),
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

    @Test("a warning before ntn's error line doesn't hide the status")
    func warningFirst() async {
        let answer = output(5, err: "warning: a newer ntn is out\nerror: Public API request failed (404 Not Found object_not_found): gone")
        let client = NotionClient(transport: ntn(FakeNtn(answer)))
        await #expect(throws: NotionError.http(404, code: "object_not_found", message: "gone")) { try await client.me() }
    }

    @Test("a run gets an empty standard input, so a program reading it ends at once rather than waiting")
    func emptyInput() async throws {
        let output = try #require(await NtnCLI.processRunner(timeout: 10)("/bin/cat", []))
        #expect(output.status == 0)
        #expect(output.standardOutput.isEmpty)
    }

    @Test("a run past its timeout is stopped, and ends as a failed run saying so, even when a program it started still holds its output open", arguments: [
        ("/bin/sleep", ["10"]),
        ("/bin/sh", ["-c", "sleep 10 & wait"]),
    ])
    func timeout(executable: String, arguments: [String]) async throws {
        let started = Date()
        let output = try #require(await NtnCLI.processRunner(timeout: 0.2)(executable, arguments))
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(output.status == NtnCLI.timedOut)
        let client = NotionClient(transport: NtnCLI(home: "/none", isExecutable: { $0 == "/bin/ntn" }, pathEnvironment: "/bin", run: { _, _ in output }))
        await #expect(throws: NotionError.network("ntn: error: didn't answer within 0 seconds")) { try await client.me() }
    }

    @Test("a run past its timeout also stops a program it started, so that program can't outlive it")
    func timeoutStopsChildren() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ntn-child-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = await NtnCLI.processRunner(timeout: 0.5)("/bin/sh", ["-c", "sleep 30 & echo $! > '\(file.path)'; wait"])
        let child = try #require(pid_t(String(decoding: try Data(contentsOf: file), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = Date().addingTimeInterval(3)
        while kill(child, 0) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(kill(child, 0) != 0)
    }

    @Test("a task cancelled before the run starts never launches it")
    func cancelledFirst() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await NtnCLI.processRunner(timeout: 10)("/bin/sleep", ["10"])
        }
        let started = Date()
        #expect(await task.value == nil)
        #expect(Date().timeIntervalSince(started) < 5)
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
