import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// A ping sent `minutesAgo` minutes before a fixed moment, in whole seconds
/// (the list's dates carry no fractions).
private func ping(_ id: String, minutesAgo: Int, title: String = "a question", body: String? = nil) -> Ping {
    Ping(
        id: id,
        title: title,
        projects: [],
        sent: Date(timeIntervalSince1970: 1_790_000_000 - Double(minutesAgo * 60)),
        body: body
    )
}

@Suite struct PingListTests {
    @Test func everyFieldAPingIsSentWithRoundTrips() throws {
        let sent = Date(timeIntervalSince1970: 1_790_000_000)
        let pings = [
            Ping(id: "cache-question", title: "Which cache?", projects: ["shop", "blog"], sent: sent,
                 repository: "yahyabedirhan/shop", body: "Redis or memcached", sender: "claude",
                 action: .herdr("w1:p3"), instance: "6F1E2B9A-0000-4000-8000-000000000001"),
            Ping(id: "k7qm2x", title: "Review ready", projects: [], sent: sent.addingTimeInterval(-60),
                 action: .url(URL(string: "https://github.com/yahyabedirhan/shop/pull/7")!)),
            Ping(id: "app-one", title: "Open it", projects: ["shop"], sent: sent.addingTimeInterval(-120),
                 action: .app("com.anthropic.claudefordesktop")),
        ]

        let list = try PingList.decode(PingList.encode(pings, shipyardVersion: "0.0.6"))

        #expect(list == PingList(version: 1, shipyardVersion: "0.0.6", pings: pings, truncated: false))
    }

    @Test func seenAndFailureStayOnTheMachine() throws {
        var seen = ping("seen-one", minutesAgo: 1)
        seen.seen = Date(timeIntervalSince1970: 1_790_000_000)
        seen.failure = "no such app"

        let text = PingList.encode([seen])
        let list = try PingList.decode(text)

        #expect(!text.contains("seen\""))
        #expect(!text.contains("failure"))
        #expect(list.pings == [ping("seen-one", minutesAgo: 1)])
    }

    @Test func theDocumentNamesItsVersionAndTheShipyardThatMadeIt() throws {
        let text = PingList.encode([], shipyardVersion: "0.0.6")

        #expect(text == #"{"pings":[],"shipyardVersion":"0.0.6","truncated":false,"version":1}"#)
        #expect(try PingList.decode(text).shipyardVersion == "0.0.6")
    }

    @Test func pingsAreListedNewestFirst() throws {
        let pings = [ping("b", minutesAgo: 5), ping("a", minutesAgo: 1), ping("c", minutesAgo: 9)]

        let list = try PingList.decode(PingList.encode(pings))

        #expect(list.pings.map(\.id) == ["a", "b", "c"])
    }

    @Test func atMostAHundredPingsAreListedAndTheRestMarkedTruncated() throws {
        let pings = (0..<150).map { ping("p\($0)", minutesAgo: $0) }

        let list = try PingList.decode(PingList.encode(pings))

        #expect(list.pings.map(\.id) == (0..<100).map { "p\($0)" })
        #expect(list.truncated)
    }

    @Test func aHundredPingsExactlyIsNotTruncated() throws {
        let pings = (0..<100).map { ping("p\($0)", minutesAgo: $0) }

        let list = try PingList.decode(PingList.encode(pings))

        #expect(list.pings.count == 100)
        #expect(!list.truncated)
    }

    @Test func longPingsStopAtTheByteBudgetAsAWholeDocument() throws {
        let body = String(repeating: "é", count: 2_000)  // 4 000 bytes each
        let pings = (0..<40).map { ping("p\($0)", minutesAgo: $0, body: body) }

        let text = PingList.encode(pings)
        let list = try PingList.decode(text)

        #expect(text.utf8.count <= PingList.byteBudget)
        #expect(PingList.byteBudget < 64 * 1024)
        #expect(list.truncated)
        #expect(list.pings.count < 40)
        #expect(list.pings.map(\.id) == (0..<list.pings.count).map { "p\($0)" })
        // The next ping would not have fit.
        let one = PingList.encode(Array(pings.prefix(list.pings.count + 1)))
        #expect(try PingList.decode(one).pings.count == list.pings.count)
    }

    @Test func aNewestPingTooLongForTheBudgetListsNoneAndSaysSo() throws {
        let huge = ping("huge", minutesAgo: 0, body: String(repeating: "x", count: 70_000))

        let text = PingList.encode([huge, ping("small", minutesAgo: 1)])
        let list = try PingList.decode(text)

        #expect(text.utf8.count <= PingList.byteBudget)
        #expect(list.pings.isEmpty)
        #expect(list.truncated)
    }

    @Test func anotherMajorVersionIsRefusedWithAWayOut() {
        let text = #"{"version":2,"shipyardVersion":"0.1.0","pings":"another shape","truncated":false}"#

        #expect(throws: PingList.DecodeError.unsupportedVersion(2, shipyardVersion: "0.1.0")) {
            try PingList.decode(text)
        }
        let message = PingList.DecodeError.unsupportedVersion(2, shipyardVersion: "0.1.0").message(machine: "netcup-vps")
        #expect(message.contains("update shipyard on netcup-vps"))
    }

    @Test func unknownFieldsAndActionKindsAreIgnored() throws {
        let text = """
            {"version":1,"shipyardVersion":"0.0.9","truncated":false,"machine":"later",
             "pings":[{"id":"a","title":"t","projects":[],"sent":"2026-10-02T10:00:00Z",
                       "priority":"high","action":{"sound":"Glass"}}]}
            """

        let list = try PingList.decode(text)

        #expect(list.pings == [Ping(id: "a", title: "t", projects: [], sent: try #require(ISO8601DateFormatter().date(from: "2026-10-02T10:00:00Z")))])
    }

    @Test func somethingElseIsUnreadable() {
        #expect(throws: PingList.DecodeError.self) { try PingList.decode("Error: no such action") }
        #expect(throws: PingList.DecodeError.unreadable("version is missing")) { try PingList.decode("{}") }
        #expect(throws: PingList.DecodeError.self) {
            try PingList.decode(#"{"version":1,"shipyardVersion":"0.0.6","pings":[{"id":"a"}],"truncated":false}"#)
        }
    }
}
