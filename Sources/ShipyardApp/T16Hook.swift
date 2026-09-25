// T16HOOK: temporary verification hook, removed before handing back.
import Foundation
import ShipyardCore

@MainActor
enum T16Hook {
    static func run(_ notifier: Notifier) {
        guard ProcessInfo.processInfo.environment["SHIPYARD_T16"] == "notify" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            await notifier.post(PostedNotification(
                id: "t16-test-\(Int(Date().timeIntervalSince1970))",
                event: .prOpened, project: "e-commerce", headline: "New PR #57",
                itemTitle: "Add order export",
                itemURL: URL(string: "https://github.com/yahyabedirhan/shipyard/pull/21")!
            ))
        }
    }
}
