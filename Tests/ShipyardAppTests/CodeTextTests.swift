import Foundation
@testable import ShipyardApp
import ShipyardCore
import SwiftUI
import Testing

@Suite("Code text")
struct CodeTextTests {
    @Test("a code span is monospaced in its ink on a chip, so gh reads as a command, and the words around it aren't")
    func codeSpan() {
        let text = CodeText.attributed("Connect with `gh`", size: 12, weight: .medium, chip: .red, ink: .pink)
        #expect(String(text.characters) == "Connect with \u{2009}gh\u{2009}")
        #expect(text.runs.count == 4)
        let gh = text.runs.first { String(text[$0.range].characters) == "gh" }
        let words = text.runs.first { String(text[$0.range].characters) == "Connect with " }
        let monospaced = Font.system(size: 12, weight: .medium, design: .monospaced)
        let plain = Font.system(size: 12, weight: .medium)
        #expect(gh?.font == monospaced)
        #expect(gh?.backgroundColor == .red)
        #expect(gh?.foregroundColor == .pink)
        #expect(words?.font == plain)
        #expect(words?.backgroundColor == nil)
        #expect(words?.foregroundColor == nil)
    }

    @Test("every gh in the connect screen's words comes out monospaced", arguments: [
        PanelText.connect(.userSignedOut(.ghStillSignedIn), canSignIn: true).message,
        PanelText.connect(.rejected(.gh), canSignIn: true).message,
        PanelText.connect(.noToken, canSignIn: false).message,
        PanelText.connectWithGh, PanelText.useGhInstead, PanelText.useGhInsteadHelp, PanelText.installGhHelp,
    ])
    func everyGh(markdown: String) {
        let text = CodeText.attributed(markdown, size: 12, chip: .red, ink: .pink)
        let gh = text.runs.filter { String(text[$0.range].characters) == "gh" }
        #expect(!gh.isEmpty)
        for run in gh {
            #expect(run.font == .system(size: 12, weight: .regular, design: .monospaced))
        }
    }

    @Test("a link stays a link")
    func link() {
        let text = CodeText.attributed(PanelText.installGh, size: 12, chip: .red, ink: .pink)
        #expect(text.runs.contains { $0.link == URL(string: "https://cli.github.com") })
    }

    @Test("every path and command a setup card, the Notion view, the notes banner or the picker names is a code span", arguments: [
        (PanelText.cliLink(.unlinked, command: "ln").message, ["shipyard", "~/.local/bin"]),
        (PanelText.cliLink(.linked, command: "ln").message, [CLILink.displayPath, "shipyard", "~/.local/bin", "PATH"]),
        (PanelText.cliLink(.occupied(destination: "/opt/homebrew/bin/shipyard"), command: "ln").message, [CLILink.displayPath, "/opt/homebrew/bin/shipyard"]),
        (PanelText.skillInstall(.running).message, ["npx"]),
        (PanelText.skillInstall(.finished(.npxNotFound(command: "npx"))).message, ["npx"]),
        (PanelText.notesNotice(.ntnMissing), ["ntn", "ntn login"]),
        (PanelText.notesNotice(.noEntryPage), ["ntn", "ntn doctor"]),
        (PanelText.addedToBrokenFile, ["config.toml"]),
    ] as [(String, [String])])
    func pathsAndCommands(markdown: String, code: [String]) {
        let text = CodeText.attributed(markdown, size: 12, chip: .red, ink: .pink)
        let spans = Set(text.runs.filter { $0.foregroundColor == .pink }.map { String(text[$0.range].characters) })
        #expect(spans == Set(code))
    }
}
