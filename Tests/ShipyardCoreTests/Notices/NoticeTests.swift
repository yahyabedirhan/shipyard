import Foundation
import ShipyardConfig
@testable import ShipyardCore
import ShipyardNotices
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// `[[defaults.notifications]]` blocks for `events`.
private func rules(_ events: [String]) -> String {
    events.map { "[[defaults.notifications]]\nevent = \"\($0)\"\n\n" }.joined()
}

/// A project watching `yahyabedirhan/shop` with its own notification list, `list`.
private func project(_ name: String, notifying list: String? = nil) -> String {
    "[[projects]]\nslug = \"\(name)\"\nrepositories = [\"yahyabedirhan/shop\"]\n" + (list.map { "notifications = \($0)\n" } ?? "") + "\n"
}

/// An agent's notice handed to the app as the control socket hands it
/// (`Shipyard.show(_:)`): whether the rules show it, under which project,
/// what's posted, and that nothing else changes. Prior art:
/// `PingNotificationTests`, `NotificationTests`.
@Suite("An agent's notice")
@MainActor
struct NoticeTests {
    /// A signed-out app with `config`, started: notices need no GitHub.
    func app(_ config: String, resolved: [String: [String]] = [:]) async throws -> Harness {
        let harness = try Harness(config: config)
        if !resolved.isEmpty { try harness.repositoriesStore.record(resolved) }
        await harness.shipyard.start()
        return harness
    }

    @Test("a notice filed by its repository posts one notification, titled with the project and its title, over its body and sender")
    func shown() async throws {
        let harness = try await app(shop)
        let menu = harness.shipyard.menu

        let verdict = await harness.shipyard.show(Notice(
            title: "Tests running", body: "12 of 40 passed", sender: "claude", repository: "YahyaBedirhan/Shop"
        ))

        #expect(verdict == .shown)
        let posted = try #require(harness.notifier.posted.first)
        #expect(harness.notifier.posted.count == 1)
        #expect(posted.event == .agentNotice)
        #expect(posted.title == "shop · Tests running")
        #expect(posted.body == "12 of 40 passed\nfrom claude")
        // Never kept, counted or listed.
        #expect(harness.shipyard.menu == menu)
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("agent.notice is on by default and follows the rules: a project whose list leaves it out refuses the notice and posts nothing", arguments: [
        // The built-in defaults hold it.
        (shop, nil),
        // A written default list replaces them.
        (rules(["pr.opened", "ping.sent"]) + shop, "notices are off for project `shop`"),
        (rules(["agent.notice"]) + shop, nil),
        // A project's own list replaces the defaults, either way.
        (project("shop", notifying: #"[{ event = "pr.opened" }]"#), "notices are off for project `shop`"),
        (project("shop", notifying: "[]"), "notices are off for project `shop`"),
        (rules(["pr.opened"]) + project("shop", notifying: #"[{ event = "agent.notice" }]"#), nil),
        // A notice has no author, so a rule with authors never selects it.
        (project("shop", notifying: #"[{ event = "agent.notice", authors = ["me"] }]"#), "notices are off for project `shop`"),
    ] as [(String, String?)])
    func followsRules(config: String, refusal: String?) async throws {
        let harness = try await app(config)

        let verdict = await harness.shipyard.show(Notice(title: "Done", repository: "yahyabedirhan/shop"))

        if let refusal {
            #expect(verdict == .refused(refusal))
            #expect(harness.notifier.posted.isEmpty)
        } else {
            #expect(verdict == .shown)
            #expect(harness.notifier.posted.map(\.title) == ["shop · Done"])
        }
    }

    @Test("a repository two projects watch shows under the first whose rules select it, and is refused, naming both, when neither does")
    func severalProjects() async throws {
        let off = #"[{ event = "pr.opened" }]"#
        let oneOn = try await app(project("shop", notifying: off) + project("store"))
        let bothOff = try await app(project("shop", notifying: off) + project("store", notifying: off))

        #expect(await oneOn.shipyard.show(Notice(title: "Done", repository: "yahyabedirhan/shop")) == .shown)
        #expect(oneOn.notifier.posted.map(\.title) == ["store · Done"])
        #expect(await bothOff.shipyard.show(Notice(title: "Done", repository: "yahyabedirhan/shop"))
            == .refused("notices are off for projects `shop`, `store`"))
        #expect(bothOff.notifier.posted.isEmpty)
    }

    @Test("--project files it under that project alone, whatever its repositories; one the configuration lacks is refused with the projects")
    func byProject() async throws {
        let harness = try await app(shop)

        #expect(await harness.shipyard.show(Notice(title: "Done", project: "shop")) == .shown)
        #expect(await harness.shipyard.show(Notice(title: "Done", project: "blog"))
            == .refused("no project is named `blog`; the projects are `shop`"))
        #expect(harness.notifier.posted.map(\.title) == ["shop · Done"])
    }

    @Test("--project finds a project by its title too, as an older shipyard names it, and the notification is titled with the project's title")
    func byProjectTitle() async throws {
        let harness = try await app("version = 1\n[[projects]]\nslug = \"shop\"\ntitle = \"Web shop\"\nrepositories = [\"yahyabedirhan/shop\"]\n")

        #expect(await harness.shipyard.show(Notice(title: "Done", project: "Web shop")) == .shown)
        #expect(await harness.shipyard.show(Notice(title: "Again", project: "shop")) == .shown)
        #expect(harness.notifier.posted.map(\.title) == ["Web shop · Done", "Web shop · Again"])
    }

    @Test("a repository no project watches is refused with the projects; one a group brought in, as last resolved, is filed")
    func byRepository() async throws {
        let harness = try await app(
            shop + "[[projects]]\nslug = \"mine\"\nrepositories = [\"owned\"]\n",
            resolved: ["mine": ["yahyabedirhan/blog"]]
        )

        #expect(await harness.shipyard.show(Notice(title: "Done", repository: "someone/else")) == .refused(
            "no project watches `someone/else`; pass --project <name> to file it under one; the projects are `shop`, `mine`"
        ))
        #expect(await harness.shipyard.show(Notice(title: "Done", repository: "yahyabedirhan/blog")) == .shown)
        #expect(harness.notifier.posted.map(\.title) == ["mine · Done"])
    }

    @Test("with shipyard's notifications off in System Settings a notice the rules show is refused, saying so, never `shown`")
    func notificationsOff() async throws {
        let harness = try await app(shop)
        harness.notifier.allowed = false

        let verdict = await harness.shipyard.show(Notice(title: "Done", project: "shop"))

        #expect(verdict == .refused("shipyard's notifications are off in System Settings, so this notice wasn't shown"))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("each notice is a notification of its own, and clicking one opens and marks nothing")
    func eachItsOwn() async throws {
        let harness = try await app(shop)

        _ = await harness.shipyard.show(Notice(title: "Tests running", project: "shop"))
        _ = await harness.shipyard.show(Notice(title: "Tests running", project: "shop"))

        let posted = harness.notifier.posted
        #expect(posted.count == 2)
        #expect(Set(posted.map(\.id)).count == 2)
        await harness.shipyard.openNotification(posted[0].itemURL).value
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.actions.ran.isEmpty)
    }
}
