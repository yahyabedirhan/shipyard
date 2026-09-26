import Foundation

// The connect screen's words (`ConnectView`).
extension PanelText {
    /// What the connect screen says: a title, what happened and what to do,
    /// the `gh` command to copy, and whether to point at installing `gh`.
    public struct Connect: Equatable, Sendable {
        /// The screen's heading, e.g. "Connect to GitHub".
        public var title: String
        /// What happened and what to do, ending where the command follows.
        public var message: String
        /// The `gh` command to run in a terminal, with a Copy button.
        public var command: String
        /// Whether `gh` may not be installed at all, so the screen shows `installGh`.
        public var suggestsInstallingGh: Bool
    }

    private static let ghLoginCommand = "gh auth login"
    private static let ghLogoutCommand = "gh auth logout"

    /// Where to get `gh`, as Markdown (the link is clickable in the panel).
    public static let installGh = "Get gh at [cli.github.com](https://cli.github.com) or with `brew install gh`."

    /// Shown while `start()` looks for a token, before there's a reason to show.
    public static let connecting = "Connecting to GitHub…"

    /// Said under Try again when it left shipyard signed out, for `reason`
    /// as it stands after the try, so the click doesn't look like it did nothing.
    public static func stillSignedOut(_ reason: Shipyard.SignedOutReason) -> String {
        switch reason {
        case .noToken: "gh still isn't signed in."
        case .rejected(.gh): "GitHub still rejects gh's token."
        case .rejected(.tokenStore): "GitHub still rejects the token."
        case .userSignedOut: "Still not connected."
        }
    }

    /// The connect screen for why shipyard is signed out. 0.0.x connects
    /// through `gh` only, so every way back in is `gh auth login`.
    public static func connect(_ reason: Shipyard.SignedOutReason) -> Connect {
        switch reason {
        case .noToken:
            Connect(
                title: "Connect to GitHub",
                message: "Shipyard connects to GitHub through the GitHub CLI, gh. Install it, then sign in with it in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: true
            )
        case .rejected(let source):
            Connect(
                title: source == .gh ? "GitHub rejected gh's token" : "GitHub rejected shipyard's token",
                message: "It was revoked or has expired. Sign in to gh again in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        case .userSignedOut(.ghStillSignedIn):
            Connect(
                title: "Signed out",
                message: "gh is still signed in, so Try again, or the next launch, connects again. To disconnect for good, sign gh out in a terminal:",
                command: ghLogoutCommand,
                suggestsInstallingGh: false
            )
        case .userSignedOut(.signedOut):
            Connect(
                title: "Signed out",
                message: "To connect again, sign in to gh in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        }
    }
}
