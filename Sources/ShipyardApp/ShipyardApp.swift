import AppKit
import ShipyardCore
import SwiftUI

/// The menu bar app: an icon with no Dock icon (`LSUIElement` in the
/// bundle's Info.plist) that opens the panel. The type isn't named
/// `ShipyardApp`, which is this module's name.
@main
struct ShipyardMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Panel(shipyard: appDelegate.services.shipyard, actions: appDelegate.services)
        } label: {
            MenuBarLabelView(shipyard: appDelegate.services.shipyard)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon and the attention count next to it (the model's
/// label: none at 0, or when `[menu-bar] count = "none"`). While the rate
/// budget pauses refreshing, the icon is a pause glyph.
struct MenuBarLabelView: View {
    let shipyard: Shipyard

    var body: some View {
        // Read in the view's body, so it redraws when the model changes.
        let menu = shipyard.menu
        HStack(spacing: 3) {
            Image(systemName: menu.canRefreshNow ? "sailboat" : "pause.circle")
            if let text = menu.menuBarLabel.text {
                Text(text).monospacedDigit()
            }
        }
    }
}

/// Builds the core once the app has launched and starts it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()

    func applicationDidFinishLaunching(_ notification: Notification) {
        services.start()
    }
}

/// The core with the app's adapters plugged in, and the triggers that make
/// it refresh: the configuration watcher and waking from sleep. The panel's
/// footer actions live here too.
@MainActor
final class AppServices {
    let shipyard: Shipyard
    private let opener = WorkspaceURLOpener()
    private var configWatcher: ConfigWatcher?
    private var wake: WakeObserver?

    init() {
        let configURL = ConfigStore.defaultURL()
        shipyard = Shipyard(
            configStore: ConfigStore(url: configURL),
            appStateStore: AppStateStore(directory: Self.appSupportDirectory),
            tokenStore: SessionTokenStore(),
            urlOpener: opener,
            notifier: LoggingNotifier()
        )
    }

    /// `~/Library/Application Support/Shipyard/`, where `state.json` lives.
    static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shipyard", isDirectory: true)
    }

    func start() {
        let shipyard = shipyard
        configWatcher = ConfigWatcher(file: shipyard.configStore.url) {
            Task { await shipyard.reloadConfiguration() }
        }
        configWatcher?.start()
        wake = WakeObserver {
            Task { await shipyard.refresh() }
        }
        Task { await shipyard.start() }
    }

    // MARK: - Footer actions

    func refresh() {
        Task { await shipyard.refresh() }
    }

    /// Opens `config.toml` in the user's editor, creating it with its
    /// commented header first when it's missing.
    func openConfigurationFile() {
        let url = shipyard.configStore.url
        do {
            try shipyard.configStore.createIfMissing()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        opener.openDocument(url)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
