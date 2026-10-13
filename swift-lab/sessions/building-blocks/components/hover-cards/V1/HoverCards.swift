import LabHost
import SwiftUI

/// The panel's hover help, drawn without the hover: a line of help, a line
/// of Markdown, and the card a row shows after a second's rest, for a pull
/// request, an issue, a workflow run and a ping.
public let variant = LabVariant { HoverCardSheet() }

struct HoverCardSheet: View {
    var body: some View {
        let rows = [Gallery.rows[0], Gallery.rows[6], Gallery.rows[10], Gallery.rows[11]]
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Specimen(title: "text") { HoverHelpCard(content: .text(PanelText.refreshHelp)) }
                Specimen(title: "markdown") { HoverHelpCard(content: .markdown("Run `shipyard ping` from any agent")) }
                Specimen(title: "two lines") { HoverHelpCard(content: .text("Mona Lisa (@octocat) · Open profile on GitHub\nSigned in since Monday")) }
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Specimen(title: row.kind.commandName) {
                        HoverHelpCard(content: .row(PanelText.rowCard(row, now: Gallery.now)))
                            .frame(maxWidth: HoverHelp.maxWidth, alignment: .leading)
                    }
                }
            }
        }
        .padding(24)
        .background(Palette.panel)
    }
}
