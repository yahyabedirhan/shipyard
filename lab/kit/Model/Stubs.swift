import Foundation

// Stand-ins for app types the copied views and model only pass through:
// GitHub's errors, the refresh pacing, the footer's rate indicator, remote
// machines' notices and the menu bar count style. The lab has no backend,
// so each holds just enough for the copied code to compile and for
// fixtures to set.

public enum GitHubError: Equatable, Sendable {
    case rateLimited
    case secondaryLimit
    case other(String)
}

public struct RefreshDelay: Equatable, Sendable {
    public var isPaused = false
    public init(isPaused: Bool = false) { self.isPaused = isPaused }
}

public struct RateIndicator: Equatable, Sendable {
    public init() {}
}

public struct MachineNotice: Equatable, Sendable {
    public var machine: String
    public var text: String
    public init(machine: String, text: String) {
        self.machine = machine
        self.text = text
    }
}

/// `[menu-bar] count`.
public enum MenuBarCount: String, Sendable {
    case total
    case perKind = "per-kind"
    case none
}

/// What GitHub's rate-limit text says about a limit.
public enum RateLevel: Equatable, Sendable {
    case normal
    case low
    case exhausted
}

/// The signed-in account, as the header names it.
public struct Viewer: Equatable, Sendable {
    public var login: String
    public var name: String?
    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }
}

extension PanelText {
    /// Copied from `PanelText+Notes.swift`: the new-note icon's hover help.
    public static func newNoteHelp(_ project: String) -> String {
        "New note in \(project)"
    }
}
