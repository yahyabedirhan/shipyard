import LabHost
import SwiftUI

/// The rows that aren't items: a repository that couldn't be fetched, a
/// note about the list, a tab with nothing to list, and the loading skeleton.
public let variant = LabVariant { StatusRowSheet() }

struct StatusRowSheet: View {
    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 4) {
                ErrorRow(error: MenuErrorRow(RepositoryError(repository: "shipyard-lab/gone", kind: .notFound, message: "")))
                ErrorRow(error: MenuErrorRow(RepositoryError(repository: "shipyard-lab/saml", kind: .forbidden, message: "Resource protected by organization SAML enforcement. You must grant your token access to this organization.")))
                ErrorRow(error: MenuErrorRow(.notes("can't reach Notion (the request timed out)")))
                NoteRow(note: PanelText.reviewSearchLimit(shown: 100, total: 164))
                Hairline().padding(.vertical, 4)
                EmptyTab(text: "Nothing open in Harbor", isLoaded: true)
                EmptyTab(text: "Loading…", isLoaded: false)
                Hairline().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonRow(width: 180)
                    SkeletonRow(width: 240)
                    SkeletonRow(width: 140)
                }
                .padding(.horizontal, Grid.gutter)
                .padding(.bottom, 10)
            }
            .padding(.vertical, 6)
        }
        .padding(20)
    }
}
