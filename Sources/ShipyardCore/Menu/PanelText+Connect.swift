import Foundation

// The connect screen's words (`ConnectView`).
extension PanelText {
    /// What the connect screen says: a title, what happened, Sign in with
    /// GitHub (or why it's unavailable), then the `gh` way in: a lead-in, the
    /// command to copy, and whether to point at installing `gh`.
    public struct Connect: Equatable, Sendable {
        /// The screen's heading, e.g. "Connect to GitHub".
        public var title: String
        /// What happened and what to do.
        public var message: String
        /// Why Sign in with GitHub can't be used in this build, shown under
        /// its disabled button; `nil` when it can.
        public var signInUnavailable: String?
        /// The words before the `gh` command, ending where the command follows.
        public var commandLead: String
        /// The `gh` command to run in a terminal, with a Copy button.
        public var command: String
        /// Whether `gh` may not be installed at all, so the screen shows `installGh`.
        public var suggestsInstallingGh: Bool
    }

    /// What the code screen says while the device flow waits for approval.
    public struct DeviceCodeScreen: Equatable, Sendable {
        /// The screen's heading.
        public var title: String
        /// The user code, shown large, e.g. "WDJB-MJHT".
        public var code: String
        /// What to do with the code.
        public var message: String
        /// The button that copies the code and opens the page to enter it on.
        public var openButton: String
        /// Under the code while polling, with when the code expires.
        public var waiting: String
    }

    private static let ghLoginCommand = "gh auth login"
    private static let ghLogoutCommand = "gh auth logout"

    /// Where to get `gh`, as Markdown (the link is clickable in the panel).
    public static let installGh = "Get gh at [cli.github.com](https://cli.github.com) or with `brew install gh`."

    /// Shown while `start()` looks for a token, before there's a reason to show.
    public static let connecting = "Connecting to GitHub…"

    /// The device flow's button on the connect screen.
    public static let signInWithGitHub = "Sign in with GitHub"

    /// Why Sign in with GitHub is off: the build's OAuth App client ID is
    /// still the placeholder.
    public static let signInUnavailable = "Not available in this build: it has no OAuth App client ID."

    /// The code screen's button that stops the device flow.
    public static let cancelSignIn = "Cancel"

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

    /// The connect screen for why shipyard is signed out. With `canSignIn`
    /// (the build has an OAuth App client ID) it leads with Sign in with
    /// GitHub and offers `gh` beside it; without, `gh` is the way in and the
    /// button says why it's unavailable.
    public static func connect(_ reason: Shipyard.SignedOutReason, canSignIn: Bool) -> Connect {
        let unavailable = canSignIn ? nil : signInUnavailable
        switch reason {
        case .noToken:
            return Connect(
                title: "Connect to GitHub",
                message: canSignIn
                    ? "Sign in with GitHub in your browser, or connect through the GitHub CLI, gh, if you use it."
                    : "Shipyard connects to GitHub through the GitHub CLI, gh.",
                signInUnavailable: unavailable,
                commandLead: canSignIn
                    ? "With gh installed, sign in with it in a terminal:"
                    : "Install it, then sign in with it in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: true
            )
        case .rejected(.gh):
            return Connect(
                title: "GitHub rejected gh's token",
                message: canSignIn
                    ? "It was revoked or has expired. Sign in with GitHub instead, or sign in to gh again."
                    : "It was revoked or has expired.",
                signInUnavailable: unavailable,
                commandLead: "Sign in to gh again in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        case .rejected(.tokenStore):
            return Connect(
                title: "GitHub rejected shipyard's token",
                message: canSignIn
                    ? "It was revoked or has expired. Sign in with GitHub again."
                    : "It was revoked or has expired.",
                signInUnavailable: unavailable,
                commandLead: canSignIn ? "Or sign in to gh in a terminal:" : "Sign in to gh in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        case .userSignedOut(.ghStillSignedIn):
            return Connect(
                title: "Signed out",
                message: "gh is still signed in, so Try again, or the next launch, connects again.",
                signInUnavailable: unavailable,
                commandLead: "To disconnect for good, sign gh out in a terminal:",
                command: ghLogoutCommand,
                suggestsInstallingGh: false
            )
        case .userSignedOut(.signedOut):
            return Connect(
                title: "Signed out",
                message: canSignIn ? "To connect again, Sign in with GitHub." : "To connect again, use gh.",
                signInUnavailable: unavailable,
                commandLead: canSignIn ? "Or sign in to gh in a terminal:" : "Sign in to gh in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        }
    }

    /// The code screen for `code`, with its expiry as the user's clock shows it.
    public static func deviceCode(
        _ code: DeviceCode,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> DeviceCodeScreen {
        let page = [code.verificationURL.host, code.verificationURL.path]
            .compactMap { $0 }
            .joined()
        return DeviceCodeScreen(
            title: "Enter this code on GitHub",
            code: code.userCode,
            message: "Copy the code, open \(page) and paste it there. Shipyard connects once you approve.",
            openButton: "Copy code and open GitHub",
            waiting: "Waiting for approval · the code expires at \(clockTime(code.expiresAt, locale: locale, timeZone: timeZone))"
        )
    }

    /// Why the last Sign in with GitHub ended without a token.
    public static func signInFailed(_ error: DeviceFlowError) -> String {
        switch error {
        case .expired: "The code expired before it was approved. Sign in again for a new one."
        case .denied: "The sign-in was declined on GitHub."
        case .clientIDMissing: signInUnavailable
        case .unauthorized: "GitHub refused the sign-in. Try again, or use gh."
        case .rejected(let code): "GitHub refused the sign-in (\(code)). Try again, or use gh."
        case .http(let status): "GitHub answered with an error (HTTP \(status)). Try again."
        case .network: "GitHub couldn't be reached. Check the connection and try again."
        case .malformed: "GitHub's answer couldn't be read. Try again."
        }
    }
}
