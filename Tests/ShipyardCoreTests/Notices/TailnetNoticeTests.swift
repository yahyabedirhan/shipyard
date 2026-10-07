import Foundation
import Observation
import ShipyardConfig
@testable import ShipyardCore
import ShipyardNotices
import Testing

/// A notice from another machine, handed to the app as its tailnet
/// listener hands it (`Shipyard.receive(_:from:)`), with the login `tailscale
/// serve` put on the request: shown only for the Mac's own Tailscale login,
/// and then by the same rules as a notice from the Mac. Prior art:
/// `NoticeTests`.
@Suite("A notice over the tailnet")
@MainActor
struct TailnetNoticeTests {
    static let shop = """
        [[projects]]
        slug = "shop"
        repositories = ["yahyabedirhan/shop"]

        """

    /// A signed-out app with `config`, started, on a Mac whose own
    /// Tailscale login is `own`.
    func app(_ config: String = shop, own: Result<String, TailnetLoginUnknown> = .success("me@example.com")) async throws -> Harness {
        let harness = try Harness(config: config)
        harness.tailnet.set(own)
        await harness.shipyard.start()
        return harness
    }

    @Test("a notice from the Mac's own login is shown under its project, as one from the Mac is")
    func ownLogin() async throws {
        let harness = try await app()

        let verdict = await harness.shipyard.receive(.show(Notice(title: "Deployed", sender: "claude", repository: "yahyabedirhan/shop")), from: "me@example.com")

        #expect(verdict == .shown)
        #expect(harness.notifier.posted.map(\.title) == ["shop · Deployed"])
        #expect(harness.notifier.posted.map(\.body) == ["from claude"])
    }

    @Test("a notice without a login, or with another's, is refused and nothing is posted", arguments: [
        (nil, "the request carried no Tailscale login, so shipyard refused it; send it through tailscale serve from one of your own untagged machines"),
        ("", "the request carried no Tailscale login, so shipyard refused it; send it through tailscale serve from one of your own untagged machines"),
        ("someone@example.com", "`someone@example.com` isn't this Mac's Tailscale login, so shipyard refused it; it takes only your own machines' notices"),
        ("Me@example.com", "`Me@example.com` isn't this Mac's Tailscale login, so shipyard refused it; it takes only your own machines' notices"),
    ] as [(String?, String)])
    func otherLogin(login: String?, refusal: String) async throws {
        let harness = try await app()

        let verdict = await harness.shipyard.receive(.show(Notice(title: "Deployed", project: "shop")), from: login)

        #expect(verdict == .refused(refusal))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("when the Mac's own login can't be learned, every notice from the tailnet is refused, saying why")
    func ownLoginUnknown() async throws {
        let harness = try await app(own: .failure(TailnetLoginUnknown("Tailscale is stopped")))

        let verdict = await harness.shipyard.receive(.show(Notice(title: "Deployed", project: "shop")), from: "me@example.com")

        #expect(verdict == .refused(
            "shipyard couldn't learn this Mac's Tailscale login (Tailscale is stopped), so it takes no notices from other machines"
        ))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("the Mac's own login is looked up for each notice, so a change of account is followed")
    func followsLogin() async throws {
        let harness = try await app()

        #expect(await harness.shipyard.receive(.show(Notice(title: "One", project: "shop")), from: "me@example.com") == .shown)
        harness.tailnet.set(.success("other@example.com"))

        #expect(await harness.shipyard.receive(.show(Notice(title: "Two", project: "shop")), from: "me@example.com") != .shown)
        #expect(await harness.shipyard.receive(.show(Notice(title: "Three", project: "shop")), from: "other@example.com") == .shown)
    }

    @Test("from the right login, a notice whose click or a button focuses Herdr is refused: the tailnet names no machine, so the Mac's own Herdr would be focused", arguments: [
        Notice(title: "Done", project: "shop", action: .herdr("w1:p3")),
        Notice(title: "Done", project: "shop", buttons: [NoticeButton(label: "Back", action: .herdr("w1:p3"))]),
    ])
    func herdrRefused(notice: Notice) async throws {
        let harness = try await app()

        let verdict = await harness.shipyard.receive(.show(notice), from: "me@example.com")

        #expect(verdict == .refused(TailnetWire.herdrRefusal))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("from the right login, notices off for the project are refused as on the Mac")
    func noticesOff() async throws {
        let harness = try await app("""
            [[projects]]
            slug = "shop"
            repositories = ["yahyabedirhan/shop"]
            notifications = [{ event = "pr.opened" }]

            """)

        let verdict = await harness.shipyard.receive(.show(Notice(title: "Deployed", project: "shop")), from: "me@example.com")

        #expect(verdict == .refused("notices are off for project `shop`"))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("a withdrawal from the Mac's own login takes the notice away; from another login nothing changes")
    func withdraw() async throws {
        let harness = try await app()

        #expect(await harness.shipyard.receive(.withdraw(id: "tests"), from: "someone@example.com")
            == .refused("`someone@example.com` isn't this Mac's Tailscale login, so shipyard refused it; it takes only your own machines' notices"))
        #expect(harness.notifier.removed.isEmpty)
        #expect(await harness.shipyard.receive(.withdraw(id: "tests"), from: "me@example.com") == .shown)
        #expect(harness.notifier.removed.count == 1)
    }

    @Test("the listening port is announced as soon as the configuration is read, while GitHub is still answering the first refresh or a reload's")
    func announcedBeforeRefresh() async throws {
        let harness = try Harness(stored: "gho_stored", config: "[notices]\nlisten = true\n" + Self.shop)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([try Harness.fixture("graphql-pull-requests.json")])
        let shipyard = harness.shipyard
        let seen = Locked<[Int?]>([])
        // What the app watches: the port, through observation, while a GitHub request is in flight.
        harness.stub.onSend { _ in
            let port = await MainActor.run { shipyard.noticeListenerPort }
            seen.withValue { $0.append(port) }
        }
        let announced = Locked(false)
        withObservationTracking { _ = shipyard.noticeListenerPort } onChange: { announced.withValue { $0 = true } }

        await shipyard.start()

        #expect(announced.current)
        #expect(seen.current.first == 47420)

        seen.withValue { $0 = [] }
        try harness.writeConfig("[notices]\nlisten = true\nport = 50000\n" + Self.shop)
        await shipyard.reloadConfiguration()
        #expect(seen.current.last == 50000)
    }

    @Test("the app listens for notices only with [notices] listen = true, on its port, and stops when the setting goes")
    func listening() async throws {
        let harness = try await app()
        #expect(harness.shipyard.noticeListenerPort == nil)

        try harness.writeConfig("[notices]\nlisten = true\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == 47420)

        try harness.writeConfig("[notices]\nlisten = true\nport = 50000\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == 50000)

        try harness.writeConfig("[notices]\nlisten = false\nport = 50000\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == nil)
    }
}
