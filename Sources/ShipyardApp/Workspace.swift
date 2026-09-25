import AppKit
import ShipyardCore

/// Opens items in the browser, and documents in their editor, through
/// `NSWorkspace`.
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        Task { @MainActor in NSWorkspace.shared.open(url) }
    }

    /// Opens a local file in the app registered for its type, or in
    /// TextEdit when none is (`.toml` often has no app).
    @MainActor
    func openDocument(_ url: URL) {
        let workspace = NSWorkspace.shared
        if workspace.urlForApplication(toOpen: url) != nil {
            workspace.open(url)
        } else if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            workspace.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
