import Foundation
@testable import ShipyardCore
import ShipyardNotices
import ShipyardPings
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// A notice's options handed to the app as the control socket hands them
/// (`Shipyard.receive(_:)`): each reaches the posted notification, an id
/// replaces and withdraws, and a click or a button runs its action as a
/// ping's click does. Prior art: `NoticeTests`, `HerdrActionTests`.
@Suite("A notice's options")
@MainActor
struct NoticeOptionsTests {
    /// A signed-out app with `config`, started: notices need no GitHub.
    func app(_ config: String = shop) async throws -> Harness {
        let harness = try Harness(config: config)
        await harness.shipyard.start()
        return harness
    }

    static let image = NoticeImage(name: "chart.png", data: Data([0x89, 0x50, 0x4E, 0x47]))

    @Test("every option reaches the posted notification: subtitle, image, sound, thread, level and each button's label")
    func everyOption() async throws {
        let harness = try await app()

        let verdict = await harness.shipyard.receive(.show(Notice(
            title: "Tests passed", body: "40 of 40", project: "shop", subtitle: "checkout", image: Self.image,
            sound: .named("Glass"), thread: "orchestration", level: .passive,
            buttons: [NoticeButton(label: "Open PR", action: .url(URL(string: "https://example.com/7")!)), NoticeButton(label: "Claude", action: .app("Claude"))]
        )))

        #expect(verdict == .shown)
        let posted = try #require(harness.notifier.posted.only)
        #expect(posted.title == "shop · Tests passed")
        #expect(posted.subtitle == "checkout")
        #expect(posted.body == "40 of 40")
        #expect(posted.image == Self.image)
        #expect(posted.sound == .named("Glass"))
        #expect(posted.thread == "agent.notice orchestration")
        #expect(posted.level == .passive)
        #expect(posted.buttons.map(\.label) == ["Open PR", "Claude"])
    }

    @Test("without options it posts as before: the default sound, its project's thread, macOS's level, no buttons, and a click that runs nothing")
    func noOptions() async throws {
        let harness = try await app()

        _ = await harness.shipyard.receive(.show(Notice(title: "Done", project: "shop")))

        let posted = try #require(harness.notifier.posted.only)
        #expect(posted.subtitle == nil && posted.image == nil && posted.level == nil && posted.thread == nil)
        #expect(posted.sound == .default)
        #expect(posted.buttons.isEmpty)
        #expect(posted.itemURL == NoticeRules.clickURL)
        #expect(posted.id.hasPrefix("agent.notice "))
    }

    @Test("--sound none posts a silent notification")
    func silent() async throws {
        let harness = try await app()

        _ = await harness.shipyard.receive(.show(Notice(title: "Done", project: "shop", sound: .silent)))

        #expect(harness.notifier.posted.map(\.sound) == [.silent])
    }

    @Test("a notice with an id is posted under it, so the next with that id replaces it in place; withdrawing the id takes it out of Notification Center")
    func replaceAndWithdraw() async throws {
        let harness = try await app()

        _ = await harness.shipyard.receive(.show(Notice(title: "Tests 3/10", project: "shop", id: "tests")))
        _ = await harness.shipyard.receive(.show(Notice(title: "Tests 10/10", project: "shop", id: "tests")))
        let withdrawn = await harness.shipyard.receive(.withdraw(id: "tests"))

        #expect(harness.notifier.posted.map(\.id) == ["agent.notice tests", "agent.notice tests"])
        #expect(harness.notifier.posted.map(\.title) == ["shop · Tests 3/10", "shop · Tests 10/10"])
        #expect(withdrawn == .shown)
        #expect(harness.notifier.removed == ["agent.notice tests"])
    }

    @Test("withdrawing an id no notice was shown under is no error, and needs no project or rules")
    func withdrawUnknown() async throws {
        let harness = try await app(#"[[projects]]"# + "\nname = \"shop\"\nrepositories = [\"yahyabedirhan/shop\"]\nnotifications = []\n")

        #expect(await harness.shipyard.receive(.withdraw(id: "never")) == .shown)
        #expect(harness.notifier.removed == ["agent.notice never"])
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("clicking the notification runs its --open or --app action through the action port", arguments: [
        PingAction.url(URL(string: "https://github.com/yahyabedirhan/shop/actions/runs/1?check=a&b=c")!),
        PingAction.app("com.anthropic.claudefordesktop"),
    ])
    func clickRuns(action: PingAction) async throws {
        let harness = try await app()
        _ = await harness.shipyard.receive(.show(Notice(title: "Done", project: "shop", action: action)))
        let posted = try #require(harness.notifier.posted.only)

        await harness.shipyard.openNotification(posted.itemURL).value

        #expect(harness.actions.ran == [action])
        #expect(harness.actions.opened.isEmpty)
    }

    @Test("a --herdr click focuses the pane in the Herdr session it was sent from, then brings forward the terminal it was sent from, as a ping's does")
    func clickHerdr() async throws {
        let harness = try await app()
        harness.herdr.open(tab: "w1:t2", panes: ["w1:p3"], inSession: "work")
        _ = await harness.shipyard.receive(.show(Notice(
            title: "Done", project: "shop", action: .herdr("w1:p3"), terminal: "com.mitchellh.ghostty", herdrSession: "work"
        )))

        await harness.shipyard.openNotification(try #require(harness.notifier.posted.only).itemURL).value

        #expect(harness.herdr.focused(inSession: "work") == ["w1:t2"])
        #expect(harness.actions.ran == [.app("com.mitchellh.ghostty")])
    }

    @Test("[herdr] terminal wins over the terminal a --herdr notice was sent from")
    func configuredTerminalWins() async throws {
        let harness = try await app("[herdr]\nterminal = \"Ghostty\"\n\n" + shop)
        harness.herdr.open(tab: "w1:t2")
        _ = await harness.shipyard.receive(.show(Notice(title: "Done", project: "shop", action: .herdr("w1:t2"), terminal: "com.apple.Terminal")))

        await harness.shipyard.openNotification(try #require(harness.notifier.posted.only).itemURL).value

        #expect(harness.herdr.focused == ["w1:t2"])
        #expect(harness.actions.ran == [.app("Ghostty")])
    }

    @Test("each button runs its own action, and the click runs the notice's own")
    func buttonsRun() async throws {
        let harness = try await app()
        harness.herdr.open(tab: "w1:t2")
        let link = URL(string: "https://example.com/pr/7")!
        _ = await harness.shipyard.receive(.show(Notice(
            title: "Done", project: "shop", action: .app("Claude"),
            buttons: [
                NoticeButton(label: "Open PR", action: .url(link)),
                NoticeButton(label: "Tab", action: .herdr("w1:t2")),
                NoticeButton(label: "Mail", action: .app("Mail")),
            ]
        )))
        let posted = try #require(harness.notifier.posted.only)

        for button in posted.buttons { await harness.shipyard.openNotification(button.url).value }
        await harness.shipyard.openNotification(posted.itemURL).value

        #expect(harness.actions.ran == [.url(link), .app("Mail"), .app("Claude")])
        #expect(harness.herdr.focused == ["w1:t2"])
    }
}

private extension Array {
    /// The one element, or `nil` when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
