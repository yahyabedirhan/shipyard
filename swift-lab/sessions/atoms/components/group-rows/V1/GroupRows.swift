import LabHost
import SwiftUI

/// What sits between a tab's rows: a kind's subheader (open, folded, with
/// attention), the Show more row of a capped group, and a divider.
public let variant = LabVariant { GroupRowSheet() }

struct GroupRowSheet: View {
    @State private var highlight = RowHighlight()

    var body: some View {
        let open = Gallery.group("Pull requests", rows: Gallery.rows(.pullRequest))
        let folded = Gallery.group("Issues", rows: Gallery.rows(.issue), folded: true)
        let capped = Gallery.group("Workflow runs", rows: Gallery.rows(.workflowRun), hidden: 12)
        PanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                GroupHeader(group: open, place: .groupHeader(open.id, in: nil), highlight: $highlight, actions: Gallery.actions)
                GroupHeader(group: folded, place: .groupHeader(folded.id, in: nil), highlight: $highlight, actions: Gallery.actions)
                ShowMoreRow(group: capped, place: .showMore(capped.id, in: nil), highlight: $highlight, actions: Gallery.actions)
                GroupDivider().padding(.vertical, 2)
                Hairline()
            }
            .padding(.vertical, 8)
            .rowHighlight(highlight)
        }
        .padding(20)
    }
}
