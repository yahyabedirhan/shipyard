import LabHost
import SwiftUI

/// The panel's button styles and its small action buttons.
public let variant = LabVariant { ButtonSheet() }

struct ButtonSheet: View {
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Specimen(title: "IconButtonStyle, regular and compact") {
                HStack(spacing: 6) {
                    Button { taps += 1 } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(IconButtonStyle()).labID("icon")
                    Button { taps += 1 } label: { Image(systemName: "rectangle.split.3x1") }.buttonStyle(IconButtonStyle())
                    Button { taps += 1 } label: { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(IconButtonStyle(compact: true))
                    NewNoteIcon(project: "Harbor", state: .ready) { taps += 1 }
                    NewNoteIcon(project: "Harbor", state: .starting) {}
                    DismissButton { taps += 1 }
                }
            }
            Specimen(title: "TextButtonStyle and MarkSeenButton") {
                HStack(spacing: 12) {
                    Button(PanelText.markAllSeen) { taps += 1 }.buttonStyle(TextButtonStyle())
                    Button("Quit") { taps += 1 }.buttonStyle(TextButtonStyle(tint: .primary, font: TypeScale.caption))
                    MarkSeenButton(title: "Mark all seen") { taps += 1 }
                }
            }
            Specimen(title: "PillButtonStyle, plain and prominent") {
                HStack(spacing: 8) {
                    Button("Open…") { taps += 1 }.buttonStyle(PillButtonStyle())
                    Button("Connect GitHub") { taps += 1 }.buttonStyle(PillButtonStyle(prominent: true)).labID("pill")
                }
            }
            Specimen(title: "CommandBox") {
                CommandBox(command: "shipyard ping \"PR ready\" --from claude")
                    .frame(width: 340)
            }
            Text("\(taps) clicks").font(TypeScale.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .background(Palette.panel)
        .hoverHelpHost()
    }
}
