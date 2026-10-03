import Foundation
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
        name = "shop"
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

    @Test("from the right login, notices off for the project are refused as on the Mac")
    func noticesOff() async throws {
        let harness = try await app("""
            [[projects]]
            name = "shop"
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

    @Test("the app listens for notices only with [notify] listen = true, on its port, and stops when the setting goes")
    func listening() async throws {
        let harness = try await app()
        #expect(harness.shipyard.noticeListenerPort == nil)

        try harness.writeConfig("[notify]\nlisten = true\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == 47420)

        try harness.writeConfig("[notify]\nlisten = true\nport = 50000\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == 50000)

        try harness.writeConfig("[notify]\nlisten = false\nport = 50000\n" + Self.shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.noticeListenerPort == nil)
    }
}
