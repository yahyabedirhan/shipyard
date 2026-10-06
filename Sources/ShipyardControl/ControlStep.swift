import Foundation

/// What a control request does, in the words the lease banner shows while
/// it runs ("Taking a screenshot…") and once it has ended ("Took a
/// screenshot"), so the maintainer can tell whether the agent still needs
/// the panel open.
public struct ControlStep: Equatable, Sendable {
    /// While it runs: "Taking a screenshot…".
    public var doing: String
    /// Once it has ended: "Took a screenshot".
    public var done: String

    public init(doing: String, done: String) {
        self.doing = doing
        self.done = done
    }
}

extension ControlRequest {
    /// The step this request is, for the banner; nil for the lease's own
    /// requests, notices and the notes check, which aren't steps in the app.
    public var step: ControlStep? {
        switch self {
        case .appStatus: ControlStep(doing: "Reading app state…", done: "Read app state")
        case .appOpen: ControlStep(doing: "Opening shipyard…", done: "Opened shipyard")
        case .appQuit: ControlStep(doing: "Quitting shipyard…", done: "Quit shipyard")
        case .panelOpen: ControlStep(doing: "Opening the panel…", done: "Opened the panel")
        case .panelClose: ControlStep(doing: "Closing the panel…", done: "Closed the panel")
        case .panelFold(let project): ControlStep(doing: "Folding \(project)…", done: "Folded \(project)")
        case .panelUnfold(let project): ControlStep(doing: "Unfolding \(project)…", done: "Unfolded \(project)")
        case .panelShowMore(let project, let kind):
            ControlStep(
                doing: "Showing all \(Self.words(kind)) in \(project)…",
                done: "Showed all \(Self.words(kind)) in \(project)"
            )
        case .panelTab(let name): ControlStep(doing: "Showing the \(name) tab…", done: "Showed the \(name) tab")
        case .screenshot(_, _, let menuBarIcon, _):
            menuBarIcon
                ? ControlStep(doing: "Taking a screenshot of the menu bar icon…", done: "Took a screenshot of the menu bar icon")
                : ControlStep(doing: "Taking a screenshot…", done: "Took a screenshot")
        case .controlTake, .controlRelease, .notify, .notesCheck: nil
        }
    }

    /// A kind as the command names it, in words: `pull-requests` is "pull requests".
    private static func words(_ kind: String) -> String {
        kind.replacingOccurrences(of: "-", with: " ")
    }
}
