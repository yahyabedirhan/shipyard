/// Where shipyard is in its lifecycle. The panel shows onboarding in the first
/// three phases and the projects in `ready`.
///
/// ```text
///           token found / device flow done
/// signedOut ─────────────────────────────▶ needsProjects ──(config has projects)──▶ ready
///     ▲                                        ▲                                    │
///     │ 401 / sign out                         └────────(projects emptied)──────────┤
///     └─────────────────────────────────────────────────────────────────────────────┘
/// ```
public enum Phase: Equatable, Sendable {
    /// No usable token: onboarding's connect step.
    case signedOut
    /// The device flow is running; the user is entering this code on github.com.
    case connecting(DeviceCode)
    /// Signed in, but the configuration has no projects: the project picker.
    case needsProjects
    /// Signed in with at least one project: refreshes run.
    case ready
}

/// What moves shipyard from one phase to another.
public enum LifecycleEvent: Equatable, Sendable {
    /// The device flow gave a code to show.
    case deviceFlowStarted(DeviceCode)
    /// The user cancelled the device flow, or its code expired.
    case deviceFlowCancelled
    /// A token was found (token store or `gh`) or the device flow finished.
    case signedIn(hasProjects: Bool)
    /// The configuration was loaded or changed.
    case configurationChanged(hasProjects: Bool)
    /// GitHub rejected the token (401), or the user signed out.
    case signedOut
}

extension Phase {
    /// The phase after `event`. Events that don't apply in the current phase
    /// leave it unchanged.
    public func after(_ event: LifecycleEvent) -> Phase {
        switch (self, event) {
        case (_, .signedOut):
            return .signedOut
        case (.signedOut, .deviceFlowStarted(let code)):
            return .connecting(code)
        case (.connecting, .deviceFlowCancelled):
            return .signedOut
        case (.signedOut, .signedIn(let hasProjects)), (.connecting, .signedIn(let hasProjects)):
            return hasProjects ? .ready : .needsProjects
        case (.needsProjects, .configurationChanged(let hasProjects)),
             (.ready, .configurationChanged(let hasProjects)):
            return hasProjects ? .ready : .needsProjects
        default:
            return self
        }
    }

    /// Whether a refresh may run in this phase.
    public var canRefresh: Bool { self == .ready }
}
