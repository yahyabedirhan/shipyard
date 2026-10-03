import Foundation
import ShipyardCommand
import ShipyardControl
import ShipyardNotices
import ShipyardPings
import Testing

/// A notice's options through `shipyard notify` on the Mac: every flag
/// lands in the one JSON shape every route carries, `withdraw` goes over
/// the same route, and misuse exits 2. What the app makes of each option
/// is `NoticeOptionsTests`'.
extension NotifyCommandTests {
    /// A folder of its own holding a PNG of `size` bytes named `chart.png`.
    static func folderWithImage(size: Int = 4) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x89, count: size).write(to: folder.appendingPathComponent("chart.png"))
        return folder
    }

    @Test("every option reaches the app in the notice's one JSON shape, the image as the file's bytes and, for a Herdr action, the terminal and session it was sent from")
    func everyOption() throws {
        let app = FakeTransport(reply: .done(""))
        let folder = try Self.folderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }

        let result = shipyard([
            "notify", "Tests passed", "--subtitle", "checkout", "--body", "40 of 40", "--from", "claude",
            "--image", "chart.png", "--sound", "none", "--thread", "orchestration", "--level", "passive", "--id", "tests",
            "--herdr", "--button", "Open PR=open:https://github.com/owner/shop/pull/7?tab=files",
            "--button", "Claude=app:Claude", "--button", "Tab=herdr:w1:t2",
        ], folder: folder, variables: ["HERDR_PANE_ID": "w1:p3", "HERDR_SESSION": "work", "TERM_PROGRAM": "ghostty"], transport: app)

        #expect(result == CommandResult(output: "shown\n"))
        #expect(app.requests == [.notify(.show(Notice(
            title: "Tests passed", body: "40 of 40", sender: "claude", repository: "owner/shop", subtitle: "checkout",
            image: NoticeImage(name: "chart.png", data: Data(repeating: 0x89, count: 4)), sound: .silent,
            thread: "orchestration", level: .passive, id: "tests", action: .herdr("w1:p3"),
            buttons: [
                NoticeButton(label: "Open PR", action: .url(URL(string: "https://github.com/owner/shop/pull/7?tab=files")!)),
                NoticeButton(label: "Claude", action: .app("Claude")),
                NoticeButton(label: "Tab", action: .herdr("w1:t2")),
            ],
            terminal: "com.mitchellh.ghostty", herdrSession: "work"
        )))])
        let wire = String(decoding: try #require(app.exchanges.current.only).request, as: UTF8.self)
        let notice: String = #""notice":{"action":{"herdr":"w1:p3"},"body":"40 of 40","#
            + #""buttons":[{"action":{"url":"https:\/\/github.com\/owner\/shop\/pull\/7?tab=files"},"label":"Open PR"},"#
            + #"{"action":{"app":"Claude"},"label":"Claude"},{"action":{"herdr":"w1:t2"},"label":"Tab"}],"#
            + #""from":"claude","herdrSession":"work","id":"tests","image":{"data":"iYmJiQ==","name":"chart.png"},"#
            + #""level":"passive","repository":"owner\/shop","sound":"none","subtitle":"checkout","#
            + #""terminal":"com.mitchellh.ghostty","thread":"orchestration","title":"Tests passed"}"#
        #expect(wire.contains(notice))
    }

    @Test("--open and --app are a click's action; without a Herdr action no terminal or session is recorded", arguments: [
        ("--open", "https://example.com/run", PingAction.url(URL(string: "https://example.com/run")!)),
        ("--app", "com.anthropic.claudefordesktop", PingAction.app("com.anthropic.claudefordesktop")),
    ])
    func clickAction(flag: String, value: String, action: PingAction) {
        let app = FakeTransport(reply: .done(""))

        _ = shipyard(["notify", "Done", flag, value], variables: ["HERDR_SESSION": "work", "TERM_PROGRAM": "ghostty"], transport: app)

        #expect(app.requests == [.notify(.show(Notice(title: "Done", repository: "owner/shop", action: action)))])
    }

    @Test("--herdr takes an id shaped like Herdr's, and a button's bare herdr the agent's own pane")
    func herdrIDs() {
        let app = FakeTransport(reply: .done(""))

        _ = shipyard(["notify", "--herdr", "w2:t4", "Done", "--button", "Mine=herdr"], variables: ["HERDR_PANE_ID": "w1:p3"], transport: app)

        #expect(app.requests == [.notify(.show(Notice(
            title: "Done", repository: "owner/shop", action: .herdr("w2:t4"), buttons: [NoticeButton(label: "Mine", action: .herdr("w1:p3"))]
        )))])
    }

    @Test("--sound takes default or a sound's name too")
    func sounds() {
        let app = FakeTransport(reply: .done(""))

        _ = shipyard(["notify", "Done", "--sound", "default"], transport: app)
        _ = shipyard(["notify", "Done", "--sound", "Glass"], transport: app)

        #expect(app.requests == [
            .notify(.show(Notice(title: "Done", repository: "owner/shop", sound: .default))),
            .notify(.show(Notice(title: "Done", repository: "owner/shop", sound: .named("Glass")))),
        ])
    }

    @Test("an image file that can't be shown exits 2 and sends nothing")
    func badImages() throws {
        let app = FakeTransport(reply: .done(""))
        let folder = try Self.folderWithImage(size: Notice.largestImage + 1)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("text".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let missing = shipyard(["notify", "Done", "--image", "gone.png"], folder: folder, transport: app)
        let notAnImage = shipyard(["notify", "Done", "--image", folder.appendingPathComponent("notes.txt").path], folder: folder, transport: app)
        let tooLarge = shipyard(["notify", "Done", "--image", "chart.png"], folder: folder, transport: app)

        #expect(missing == CommandResult(error: "shipyard notify: `--image` can't read `gone.png`\n", status: 2))
        #expect(notAnImage == CommandResult(
            error: "shipyard notify: `--image` takes a PNG, JPEG or GIF file, not `\(folder.appendingPathComponent("notes.txt").path)`\n", status: 2
        ))
        #expect(tooLarge == CommandResult(error: "shipyard notify: `--image` `chart.png` is larger than a notice's 5 MB\n", status: 2))
        #expect(app.requests.isEmpty)
    }

    @Test("options that don't read exit 2 with what's wrong and send nothing", arguments: [
        (["--open", "https://a.example", "--app", "Claude"], "a notice's click has one action at most; pass one of --open, --app, --herdr"),
        (["--herdr", "w1:t2", "--open", "https://a.example"], "a notice's click has one action at most; pass one of --open, --app, --herdr"),
        (["--button", "A=app:A", "--button", "B=app:B", "--button", "C=app:C", "--button", "D=app:D"], "a notice has 3 buttons at most, not 4"),
        (["--level", "critical"], "`--level` takes passive or active, not `critical`"),
        (["--level", "time-sensitive"], "`--level` takes passive or active, not `time-sensitive`"),
        (["--sound", " "], "`--sound` takes default, none or a sound's name"),
        (["--thread", ""], "`--thread` takes a key the notices of one thread share"),
        (["--id", "Tests 1"], "`--id`: an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `Tests 1`"),
        (["--open", "example.com"], "`--open` takes a URL with its scheme, such as https://example.com, not `example.com`"),
        (["--app", " "], "`--app` takes an app's bundle id or name"),
        (["--herdr"], "`--herdr` without an id focuses your own pane, but HERDR_PANE_ID isn't set (you're not in Herdr); pass a tab or pane id such as w1:t2"),
        (["--button", "Open PR"], "`--button` takes \"<label>=<action>\", its action open:<url>, app:<bundle id or name> or herdr[:<tab or pane id>], not `Open PR`"),
        (["--button", "=app:Claude"], "`--button` takes \"<label>=<action>\", its action open:<url>, app:<bundle id or name> or herdr[:<tab or pane id>]; `=app:Claude` has no label"),
        (["--button", "PR=https://a.example"], "`--button` takes \"<label>=<action>\", its action open:<url>, app:<bundle id or name> or herdr[:<tab or pane id>], not `https://a.example` for `PR`"),
        (["--button", "Tab=herdr:w1"], "`--button` `Tab` takes a Herdr tab or pane id such as w1:t2 or w1:p3, not `w1`"),
        (["--button", "Mine=herdr"], "`--button` `Mine` without an id focuses your own pane, but HERDR_PANE_ID isn't set (you're not in Herdr); pass a tab or pane id such as w1:t2"),
        (["--image", ""], "`--image` takes an image file's path"),
    ])
    func misusedOptions(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["notify", "Done"] + arguments, transport: app)

        #expect(result == CommandResult(error: "shipyard notify: \(line)\n", status: 2))
        #expect(app.requests.isEmpty)
    }

    // MARK: Withdraw

    @Test("withdraw <id> asks the app over the same route to take the notice away, and prints `withdrawn`")
    func withdraw() throws {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["notify", "withdraw", "tests"], origin: nil, transport: app)

        #expect(result == CommandResult(output: "withdrawn\n"))
        #expect(app.requests == [.notify(.withdraw(id: "tests"))])
        #expect(String(decoding: try #require(app.exchanges.current.only).request, as: UTF8.self).contains(#""notice":{"withdraw":"tests"}"#))
    }

    @Test("a withdrawal the app can't take exits 1 saying so; one that doesn't read exits 2", arguments: [
        (["withdraw", "tests"], FakeTransport.nothingListens, "shipyard notify withdraw: shipyard isn't running, so the notice wasn't withdrawn\n", 1),
        (["withdraw"], FakeTransport(reply: .done("")), "shipyard notify withdraw: give the id of one notice: shipyard notify withdraw <id>\n", 2),
        (["withdraw", "a", "b"], FakeTransport(reply: .done("")), "shipyard notify withdraw: give the id of one notice: shipyard notify withdraw <id>\n", 2),
        (["withdraw", "A"], FakeTransport(reply: .done("")),
         "shipyard notify withdraw: an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `A`\n", 2),
    ] as [([String], FakeTransport, String, Int32)])
    func withdrawRefused(arguments: [String], transport: FakeTransport, error: String, status: Int32) {
        let result = shipyard(["notify"] + arguments, transport: transport)

        #expect(result == CommandResult(error: error, status: status))
    }

    @Test("after --, withdraw is a notice's title")
    func withdrawAsTitle() {
        let app = FakeTransport(reply: .done(""))

        _ = shipyard(["notify", "--", "withdraw"], transport: app)

        #expect(app.requests == [.notify(.show(Notice(title: "withdraw", repository: "owner/shop")))])
    }

    @Test("a notice request's JSON: a notice without the newer fields, as an older command sends it, reads as one to show, and {\"withdraw\":…} as a withdrawal")
    func requestJSON() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(NoticeRequest.self, from: Data(#"{"from":"claude","repository":"owner/shop","title":"Done"}"#.utf8))
            == .show(Notice(title: "Done", sender: "claude", repository: "owner/shop")))
        #expect(try decoder.decode(NoticeRequest.self, from: Data(#"{"withdraw":"tests"}"#.utf8)) == .withdraw(id: "tests"))
    }
}
