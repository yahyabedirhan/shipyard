import Foundation
@testable import ShipyardApp
import ShipyardCore
import SwiftUI
import Testing

@Suite("Code text")
struct CodeTextTests {
    @Test("a code span is monospaced on a chip, so gh reads as a command, and the words around it aren't")
    func codeSpan() {
        let text = CodeText.attributed("Connect with `gh`", size: 12, weight: .medium)
        #expect(String(text.characters) == "Connect with \u{2009}gh\u{2009}")
        let runs = text.runs.map { (String(text[$0.range].characters), $0.font, $0.backgroundColor) }
        #expect(runs.count == 4) // the words, the chip's padding, gh, the padding
        #expect(runs.first { $0.0 == "gh" }?.1 == .system(size: 12, weight: .medium, design: .monospaced))
        #expect(runs.first { $0.0 == "gh" }?.2 == CodeText.chip)
        #expect(runs.first { $0.0 == "Connect with " }?.1 == .system(size: 12, weight: .medium))
        #expect(runs.first { $0.0 == "Connect with " }?.2 == nil)
    }

    @Test("every gh in the connect screen's words comes out monospaced", arguments: [
        PanelText.connect(.userSignedOut(.ghStillSignedIn), canSignIn: true).message,
        PanelText.connect(.rejected(.gh), canSignIn: true).message,
        PanelText.connect(.noToken, canSignIn: false).message,
        PanelText.connectWithGh, PanelText.useGhInstead, PanelText.useGhInsteadHelp, PanelText.installGhHelp,
    ])
    func everyGh(markdown: String) {
        let text = CodeText.attributed(markdown, size: 12)
        let gh = text.runs.filter { String(text[$0.range].characters) == "gh" }
        #expect(!gh.isEmpty)
        for run in gh {
            #expect(run.font == .system(size: 12, weight: .regular, design: .monospaced))
        }
    }

    @Test("a link stays a link")
    func link() {
        let text = CodeText.attributed(PanelText.installGh, size: 12)
        #expect(text.runs.contains { $0.link == URL(string: "https://cli.github.com") })
    }
}
