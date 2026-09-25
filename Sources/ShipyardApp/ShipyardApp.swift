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

extension Bundle {
    /// Whether this is a `.app` bundle: false for `make run`, which runs the
    /// bare executable, where notifications and login items don't exist.
    var isAppBundle: Bool { bundleURL.pathExtension == "app" }
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
    /// The agent skill install, kept for the app's run so an install goes
    /// on, and its result stays, while the panel is closed.
    let skillInstallation = SkillInstallation()
    private let notifier = Notifier()
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
            notifier: notifier,
            loginItem: LaunchAtLogin()
        )
        let shipyard = shipyard
        notifier.onOpen = { [weak self] url in
            shipyard.openNotification(url)
            self?.closeMenu()
        }
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
        // Before a click that launched the app is handled (it's queued
        // behind this), `start()` has loaded the app state it marks seen in.
        Task { await shipyard.start() }
        Task { await notifier.checkPermission() }
    }

    // MARK: - Layout actions

    /// What the menu's layout can do: open or mark seen a row, mark a
    /// project (or every project) seen, collapse a project.
    var layoutActions: LayoutActions {
        let shipyard = shipyard
        return LayoutActions(
            open: { [weak self] row in
                shipyard.open(row)
                self?.closeMenu()
            },
            markSeen: { shipyard.markSeen($0) },
            markAllSeen: { shipyard.markAllSeen(project: $0?.name) },
            toggleCollapsed: { shipyard.toggleCollapsed($0.name) }
        )
    }

    // MARK: - Panel actions

    func refresh() {
        Task { await shipyard.refresh() }
    }

    /// Opening the panel rereads the notification permission (the user may
    /// have changed it in System Settings). It doesn't refresh: looking
    /// costs no GitHub request, the timer keeps the data fresh.
    func panelOpened() {
        Task { await notifier.checkPermission() }
    }

    /// Whether the panel says notifications are off (observed: it's the
    /// notifier's permission).
    var notificationsAreOff: Bool { notifier.isOff }

    func openNotificationSettings() {
        notifier.openSettings()
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
        closeMenu()
    }

    // MARK: - Closing the menu

    /// Closes the menu's window after an action that opened something in
    /// another app (an item, a notification's item, the configuration
    /// file), as a menu bar menu does; otherwise it stays on screen
    /// without being the key window, and keys go to the other app (#39).
    /// Actions that only change the menu (⌥-click, collapse, Mark all
    /// seen) don't call it.
    ///
    /// SwiftUI has no API to dismiss a `.window` style `MenuBarExtra`
    /// (FB11984872), and closing its window directly leaves SwiftUI
    /// thinking it's open, so the next click on the icon does nothing.
    /// This closes it the way a click on the icon does, as the
    /// MenuBarExtraAccess package does: through the status item. On
    /// macOS 26 and earlier the icon's button toggles the window; from
    /// macOS 27 the window lives for an "expanded interface session"
    /// (private, so reached by selector and guarded), which is cancelled.
    /// It runs on the next turn of the main loop, after the click that
    /// called it is handled.
    func closeMenu() {
        DispatchQueue.main.async {
            guard let item = Self.menuBarStatusItem() else { return }
            let delegate = NSSelectorFromString("expandedInterfaceDelegate")
            let session = NSSelectorFromString("expandedInterfaceSession")
            if item.responds(to: delegate), item.responds(to: session),
               item.perform(delegate)?.takeUnretainedValue() != nil {
                // macOS 27+: SwiftUI drives the window through a session
                // (the button's target is nil); it's presented while one exists.
                let cancel = NSSelectorFromString("cancel")
                if let current = item.perform(session)?.takeUnretainedValue() as? NSObject,
                   current.responds(to: cancel) {
                    current.perform(cancel)
                }
            } else if let button = item.button, button.state != .off {
                // macOS 26 and earlier: the button is on while presented.
                button.performClick(nil)
            }
        }
    }

    /// The menu bar icon's status item: the app has one, found through
    /// its status bar window (a private `NSWindow` subclass that holds it).
    private static func menuBarStatusItem() -> NSStatusItem? {
        let key = "statusItem"
        for window in NSApp.windows where window.responds(to: NSSelectorFromString(key)) {
            if let item = window.value(forKey: key) as? NSStatusItem { return item }
        }
        return nil
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
