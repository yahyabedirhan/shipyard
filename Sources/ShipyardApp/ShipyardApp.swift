import AppKit
import os
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardCore
import ShipyardNotices
import ShipyardPings
import SwiftUI

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

struct MenuBarLabelView: View {
    let shipyard: Shipyard
    let lease: LeaseIndicator

    var body: some View {
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
    var isAppBundle: Bool { bundleURL.pathExtension == "app" }
}

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

@MainActor
final class AppServices {
    let shipyard: Shipyard
    let skillInstallation = SkillInstallation()
    let skillDetector = SkillDetector(home: FileManager.default.homeDirectoryForCurrentUser)
    let cliLink = CLILink(
        cli: CLILink.bundledCLI(in: Bundle.main.bundleURL),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
    let avatars = AvatarCache(
        directory: AppServices.files.avatars,
        transport: URLSessionTransport()
    )
    private let notifier = Notifier()
    private let opener = WorkspaceActions()
    private var configWatcher: ConfigurationWatcher?
    private var themeWatcher: ConfigurationWatcher?
    private var pingWatcher: ConfigurationWatcher?
    private var wake: WakeObserver?
    let panelState = PanelState()
    private let panelControl: PanelControl
    let leaseIndicator = LeaseIndicator()
    private var controlServer: ControlServer?
    private var noticeListener: NoticeListener?
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "control")

    init() {
        let files = Self.files
        shipyard = Shipyard(
            configStore: ConfigurationStore(url: files.config),
            appStateStore: AppStateStore(directory: files.support),
            configStatusStore: ConfigStatusStore(directory: files.support),
            pingStore: PingStore(directory: files.pings),
            repositoriesStore: ResolvedRepositoriesStore(directory: files.support),
            tokenStore: Keychain.github,
            actions: opener,
            notifier: notifier,
            loginItem: files.loginItem(LaunchAtLogin()),
            notionRoute: files.notionRoute(NtnCLI()),
            demoItems: files.demoItems(at: Date())
        )
        panelControl = PanelControl(shipyard: shipyard, state: panelState, demo: files.demo)
        let shipyard = shipyard
        panelState.lookAt = { [weak self] part in self?.lookAt(part) }
        notifier.onOffChange = { shipyard.notificationsAreOff = $0 }
        leaseIndicator.onBannersChange = { if shipyard.lease != $0 { shipyard.lease = $0 } }
        notifier.onOpen = { [weak self] url in
            guard url != ControlNotice.panelURL else {
                MenuBarWindow.open()
                return
            }
            shipyard.openNotification(url)
            self?.closeMenu()
        }
    }

    static let files = AppFiles(environment: ProcessInfo.processInfo.environment)

    func start() {
        let shipyard = shipyard
        configWatcher = ConfigurationWatcher(file: shipyard.configStore.url) {
            Task { await shipyard.reloadConfiguration() }
        }
        configWatcher?.start()
        themeWatcher = ConfigurationWatcher(files: shipyard.configStore.themesFolder, matching: ThemeFiles.urls) {
            Task { await shipyard.reloadConfiguration() }
        }
        themeWatcher?.start()
        try? shipyard.pingStore.createDirectory()
        pingWatcher = ConfigurationWatcher(folder: { shipyard.pingStore.watchedDirectory }) {
            Task { await shipyard.reloadPings() }
        }
        pingWatcher?.start()
        wake = WakeObserver {
            Task { await shipyard.refresh() }
        }
        followNoticeListening()
        Task { await shipyard.start() }
        Task { await notifier.checkPermission() }
        if Self.files.demo == nil { Task.detached { Keychain.removeOldNotionToken() } }
        startControl()
    }

    private func followNoticeListening() {
        withObservationTracking {
            applyNoticeListening()
        } onChange: { [weak self] in
            Task { @MainActor in self?.followNoticeListening() }
        }
    }

    private func applyNoticeListening() {
        let wanted = shipyard.noticeListenerPort
        guard noticeListener?.port != wanted else { return }
        noticeListener?.close()
        noticeListener = nil
        guard let port = wanted else { return }
        let shipyard = shipyard
        do {
            noticeListener = try NoticeListener.start(port: port) { request, login in
                await shipyard.receive(request, from: login)
            }
        } catch {
            Self.log.error("notices from other machines are off: \(error.description, privacy: .public)")
        }
    }

    private func startControl() {
        let shipyard = shipyard
        let screenshotter = Screenshotter(panel: panelControl, indicator: leaseIndicator) { [unowned self] in
            AnyView(Panel(shipyard: shipyard, actions: self, isSnapshot: true))
        }
        let server = ControlServer(
            socket: ControlSocket.url(in: Self.files.support),
            panel: panelControl,
            screenshotter: screenshotter,
            lease: ControlLease(environment: ProcessInfo.processInfo.environment, at: Date()),
            indicator: leaseIndicator,
            transitioned: { transition in
                guard let notice = ControlNotice(transition) else { return }
                Task { await shipyard.notify(notice) }
            },
            notices: { request in await shipyard.receive(request) },
            notesCheck: {
                guard let report = await shipyard.checkNotes() else {
                    return .refused(PanelText.notesCheckRefusal(canReadNotes: shipyard.canReadNotes))
                }
                return report.hasErrors ? .refused(report.text) : .inOrder(report.text)
            },
            quit: { NSApp.terminate(nil) }
        )
        do {
            try server.start()
            controlServer = server
        } catch {
            Self.log.error("app control is off: \(error.description, privacy: .public)")
        }
    }

    func stop() {
        controlServer?.stop()
        controlServer = nil
        noticeListener?.close()
        noticeListener = nil
    }

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
            },
            openPage: { [weak self] link in
                shipyard.openPage(link)
                self?.closeMenu()
            },
            startNote: { [weak self] project in
                Task { @MainActor in
                    if await shipyard.startNote(in: project.name) { self?.closeMenu() }
                }
            }
        )
    }

    func openProfile() {
        shipyard.openProfile()
        closeMenu()
    }

    func refresh() {
        Task { await shipyard.refreshNow() }
    }

    func switchToNextLayout() {
        Task { await shipyard.switchToNextLayout() }
    }

    func panelOpened() {
        panelState.isOpen = true
        cliLink.check()
        skillDetector.check()
        Task { await notifier.checkPermission() }
        let shipyard = shipyard
        Task { await shipyard.panelOpened() }
    }

    /// A status view's check, run as the view opens (`PanelState.show`)
    /// and by its Check again.
    func lookAt(_ part: SetupPart) {
        switch part {
        case .cli: cliLink.check()
        case .skill: skillDetector.check()
        case .notion:
            let shipyard = shipyard
            Task { await shipyard.checkNotion() }
        case .github: break
        }
    }

    func panelClosed() {
        panelState.isOpen = false
        panelState.reopenGuard.panelClosed(byControl: panelState.closingByControl, at: Date())
        panelState.closingByControl = false
        panelState.show(nil)
        shipyard.panelClosed()
    }

    func openNotificationSettings() {
        notifier.openSettings()
    }

    func stopLease() {
        controlServer?.stopLease()
    }

    func allowLeaseHolder(_ key: String) {
        controlServer?.allow(key)
    }

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

    func closeMenu() {
        MenuBarWindow.close()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
