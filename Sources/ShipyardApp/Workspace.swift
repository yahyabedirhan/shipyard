import AppKit
import ShipyardCore

/// Opens items in the browser, runs pings' link and app actions (and so
/// brings `[herdr] terminal` forward), and opens documents in their editor,
/// through `NSWorkspace`.
struct WorkspaceActions: ActionRunning {
    func open(_ url: URL) {
        Task { @MainActor in NSWorkspace.shared.open(url) }
    }

    /// Opens a ping's link in the app that handles it, or brings its app
    /// forward (launching it when it isn't running).
    func run(_ action: PingAction) async -> ActionOutcome {
        switch action {
        case .url(let url):
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            return opened ? .done : .failed("Couldn't open the link")
        case .app(let app):
            return await Self.activate(app)
        case .herdr:
            // `Shipyard` focuses Herdr itself (`HerdrFocus`) and asks for
            // `[herdr] terminal` as an app; a Herdr action never comes here.
            return .failed("Couldn't focus Herdr")
        }
    }

    /// Launches or brings forward the app `app` names, by bundle id first,
    /// then by name in the usual Applications folders.
    @MainActor
    private static func activate(_ app: String) async -> ActionOutcome {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: app) ?? application(named: app) else {
            return .failed("No app named \(app)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await withCheckedContinuation { continuation in
            workspace.openApplication(at: url, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil ? .done : .failed("Couldn't open \(app)"))
            }
        }
    }

    /// `<name>.app` in `/Applications`, `~/Applications` or the system's
    /// Applications folders, if it's there.
    private static func application(named name: String) -> URL? {
        let bundle = name.hasSuffix(".app") ? name : name + ".app"
        let folders = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        ]
        return folders
            .map { $0.appendingPathComponent(bundle, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
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
