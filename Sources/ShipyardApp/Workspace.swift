import AppKit
import ShipyardCore
import ShipyardPings

struct WorkspaceActions: ActionRunning {
    func open(_ url: URL) {
        Task { @MainActor in NSWorkspace.shared.open(url) }
    }

    func run(_ action: PingAction) async -> ActionOutcome {
        switch action {
        case .url(let url):
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            return opened ? .done : .failed("Bad link", detail: "Couldn't open the link")
        case .app(let app):
            return await Self.activate(app)
        case .herdr:
            return .failed("No focus", detail: "Couldn't focus Herdr")
        }
    }

    @MainActor
    private static func activate(_ app: String) async -> ActionOutcome {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: app) ?? application(named: app) else {
            return .failed("No app", detail: "No app named \(app)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await withCheckedContinuation { continuation in
            workspace.openApplication(at: url, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil ? .done : .failed("App error", detail: "Couldn't open \(app)"))
            }
        }
    }

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
