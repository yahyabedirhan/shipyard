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
    case signedOut
    case connecting(DeviceCode)
    case needsProjects
    case ready
}

/// What moves shipyard from one phase to another.
public enum LifecycleEvent: Equatable, Sendable {
    case deviceFlowStarted(DeviceCode)
    case deviceFlowCancelled
    case signedIn(hasProjects: Bool)
    case configurationChanged(hasProjects: Bool)
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
