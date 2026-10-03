import AppKit
import os
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardCore
import ShipyardPings
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
            MenuBarLabelView(shipyard: appDelegate.services.shipyard, lease: appDelegate.services.leaseIndicator)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon, shipyard's sailboat (the app icon's figure), and the
/// attention count next to it (the model's label: none at 0, or when
/// `[menu-bar] count = "none"`). While the rate budget pauses refreshing, the
/// icon is a pause glyph. While an agent holds the lease, the icon carries
/// a yellow dot (`LeaseDot`), next to the count.
struct MenuBarLabelView: View {
    let shipyard: Shipyard
    let lease: LeaseIndicator

    var body: some View {
        // Read in the view's body, so it redraws when the model, or the lease, changes.
        let menu = shipyard.menu
        let isLeased = lease.shown(at: Date()) != nil
        HStack(spacing: 3) {
            if isLeased {
                Image(nsImage: LeaseDot.image(on: menu.canRefreshNow ? .sailboat : .paused))
            } else if menu.canRefreshNow {
                Image(nsImage: SailboatImage.menuBar())
            } else {
                Image(systemName: "pause.circle")
            }
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

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
    }
}

/// The core with the app's adapters plugged in, and the triggers that make
/// it refresh: the configuration watcher and waking from sleep. The panel's
/// footer actions live here too, and app control's server, which the
/// `shipyard` command asks through `control.sock`.
@MainActor
final class AppServices {
    let shipyard: Shipyard
    /// The agent skill install, kept for the app's run so an install goes
    /// on, and its result stays, while the panel is closed.
    let skillInstallation = SkillInstallation()
    /// The offer to link the bundled CLI into `~/.local/bin`.
    let cliLink = CLILink(
        cli: CLILink.bundledCLI(in: Bundle.main.bundleURL),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
    /// The account's avatar for the header, kept on disk.
    let avatars = AvatarCache(
        directory: AppServices.files.avatars,
        transport: URLSessionTransport()
    )
    private let notifier = Notifier()
    private let opener = WorkspaceActions()
    private var configWatcher: ConfigWatcher?
    private var pingWatcher: ConfigWatcher?
    private var wake: WakeObserver?
    /// Whether the panel is open and the tab it shows, which its views and
    /// app control both read and set.
    let panelState = PanelState()
    /// The panel as app control sees it.
    private let panelControl: PanelControl
    /// The lease as the menu bar icon's dot and the panel's banner show it,
    /// written by the control server.
    let leaseIndicator = LeaseIndicator()
    private var controlServer: ControlServer?
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "control")

    init() {
        let files = Self.files
        shipyard = Shipyard(
            configStore: ConfigStore(url: files.config),
            appStateStore: AppStateStore(directory: files.support),
            configStatusStore: ConfigStatusStore(directory: files.support),
            pingStore: PingStore(directory: files.pings),
            repositoriesStore: ResolvedRepositoriesStore(directory: files.support),
            tokenStore: Keychain(),
            actions: opener,
            notifier: notifier,
            loginItem: files.loginItem(LaunchAtLogin())
        )
        panelControl = PanelControl(shipyard: shipyard, state: panelState, demo: files.demo)
        let shipyard = shipyard
        notifier.onOpen = { [weak self] url in
            shipyard.openNotification(url)
            self?.closeMenu()
        }
    }

    /// Where the app reads and writes: `config.toml` and the support folder
    /// (`SupportFolder`'s one definition, which the CLI reads
    /// `repositories.json` from, so the two can't disagree), both moved
    /// into a demo's folder in a demo run.
    static let files = AppFiles(environment: ProcessInfo.processInfo.environment)

    func start() {
        let shipyard = shipyard
        configWatcher = ConfigWatcher(file: shipyard.configStore.url) {
            Task { await shipyard.reloadConfiguration() }
        }
        configWatcher?.start()
        // The `shipyard` CLI writes one file per ping into the store's
        // directory: watching that folder alone sees each one arrive, and
        // not the app's own saves to `state.json` beside it. The folder is
        // made before the watch opens (`Shipyard.start()` makes it too),
        // so the watch is on it from the first moment.
        try? shipyard.pingStore.createDirectory()
        pingWatcher = ConfigWatcher(folder: { shipyard.pingStore.watchedDirectory }) {
            Task { await shipyard.reloadPings() }
        }
        pingWatcher?.start()
        wake = WakeObserver {
            Task { await shipyard.refresh() }
        }
        // Before a click that launched the app is handled (it's queued
        // behind this), `start()` has loaded the app state it marks seen in.
        Task { await shipyard.start() }
        Task { await notifier.checkPermission() }
        startControl()
    }

    /// Listens on `control.sock` for the `shipyard` command. When it can't,
    /// the app runs on without app control and says why in the log.
    private func startControl() {
        let screenshotter = Screenshotter(panel: panelControl, indicator: leaseIndicator) { [unowned self] in
            AnyView(Panel(shipyard: shipyard, actions: self, isSnapshot: true))
        }
        let server = ControlServer(
            socket: ControlSocket.url(in: Self.files.support),
            panel: panelControl,
            screenshotter: screenshotter,
            // A relaunch through `shipyard app open` hands its holder's lease over.
            lease: ControlLease(environment: ProcessInfo.processInfo.environment, at: Date()),
            indicator: leaseIndicator,
            quit: { NSApp.terminate(nil) }
        )
        do {
            try server.start()
            controlServer = server
        } catch {
            Self.log.error("app control is off: \(error.description, privacy: .public)")
        }
    }

    /// Before the app quits: stops app control and removes its socket.
    func stop() {
        controlServer?.stop()
        controlServer = nil
    }

    // MARK: - Layout actions

    /// What the menu's layout can do: open or mark seen a row, mark a
    /// project (or every project) seen, collapse a project, open a
    /// project's repository.
    var layoutActions: LayoutActions {
        let shipyard = shipyard
        return LayoutActions(
            open: { [weak self] row in
                shipyard.open(row)
                self?.closeMenu()
            },
            markSeen: { shipyard.markSeen($0) },
            dismiss: { shipyard.dismiss($0) },
            markAllSeen: { shipyard.markAllSeen(project: $0?.name) },
            toggleCollapsed: { shipyard.toggleCollapsed($0.name) },
            toggleGroup: { shipyard.toggleGroup($0.id) },
            toggleShowMore: { group in
                if group.isExpanded { shipyard.showLess(group.id) } else { shipyard.showMore(group.id) }
            },
            openRepository: { [weak self] project in
                shipyard.openRepository(of: project)
                self?.closeMenu()
            }
        )
    }

    // MARK: - Panel actions

    /// The header's avatar or handle: opens the account's profile on
    /// GitHub, then closes the menu, as opening a row does.
    func openProfile() {
        shipyard.openProfile()
        closeMenu()
    }

    /// The header's Refresh button (⌘R): also creates the configuration
    /// file when it's missing.
    func refresh() {
        Task { await shipyard.refreshNow() }
    }

    /// The header's layout button: writes the next layout to the
    /// configuration file; the menu switches with the reload.
    func switchToNextLayout() {
        Task { await shipyard.switchToNextLayout() }
    }

    /// Opening the panel rereads the notification permission (the user may
    /// have changed it in System Settings). It doesn't refresh: looking
    /// costs no GitHub request, the timer keeps the data fresh.
    func panelOpened() {
        panelState.isOpen = true
        Task { await notifier.checkPermission() }
    }

    /// Closing the panel caps every group Show more revealed, so the menu
    /// opens with every cap back.
    func panelClosed() {
        panelState.isOpen = false
        shipyard.panelClosed()
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
    /// another app (an item, a notification's item, the account's profile,
    /// the configuration file), as a menu bar menu does; otherwise it stays on screen
    /// without being the key window, and keys go to the other app.
    /// Actions that only change the menu (⌥-click, collapse, Mark all
    /// seen) don't call it. It closes it as a click on the icon does
    /// (`MenuBarWindow`).
    func closeMenu() {
        MenuBarWindow.close()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
