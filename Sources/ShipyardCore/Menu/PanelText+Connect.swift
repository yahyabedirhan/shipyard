import Foundation

// The connect screen's words (`ConnectView`).
extension PanelText {
    /// What the connect screen says, and which way in leads: a title, one
    /// line on what happened, then Sign in with GitHub and the `gh` way in
    /// the order `lead` gives. Strings mentioning `gh` are Markdown, so the
    /// command reads in code font.
    public struct Connect: Equatable, Sendable {
        /// Which way in the screen puts first.
        public enum Lead: Equatable, Sendable {
            /// Sign in with GitHub, prominent; under it the `gh` way,
            /// folded in a disclosure.
            case signIn
            /// The `gh auth login` box with Connect with gh beside it,
            /// prominent; Sign in with GitHub under it.
            case ghCommand
            /// Connect with gh, prominent, beside the message (`gh` is
            /// signed in already); Sign in with GitHub under it.
            case connectWithGh
        }

        /// The screen's greeting, e.g. "Welcome to Shipyard".
        public var title: String
        /// What happened and the quickest way in, in a line or two (Markdown).
        public var message: String
        public var lead: Lead
        /// Why Sign in with GitHub can't be used in this build, shown under
        /// its disabled button; `nil` when it can.
        public var signInUnavailable: String?
        /// Whether `gh` may not be installed at all, so the `gh` way has the
        /// install hint (`installGh`) beside it.
        public var showsInstallHint: Bool
    }

    /// What the code screen says while the device flow waits for approval.
    public struct DeviceCodeScreen: Equatable, Sendable {
        /// The screen's heading.
        public var title: String
        /// The user code, shown large, e.g. "WDJB-MJHT".
        public var code: String
        /// What to do with the code.
        public var message: String
        /// What clicking the code, or the copy icon beside it, does: the
        /// icon's VoiceOver label and the code's hint.
        public var copyCode: String
        /// The short word beside the copy icon.
        public var copyTitle: String
        /// Once the code is on the clipboard: the word beside the icon, and
        /// said in `copyCode`'s place to VoiceOver.
        public var copied: String
        /// The button that copies the code and opens the page to enter it on.
        public var openButton: String
        /// Under the code while polling, with when the code expires.
        public var waiting: String
    }

    /// The command that signs `gh` in, in the `gh` way's copyable box.
    public static let ghLogin = "gh auth login"

    /// The button that looks for `gh`'s token again (`start()`).
    public static let connectWithGh = "Connect with `gh`"

    /// The disclosure that holds the `gh` way when Sign in with GitHub leads.
    public static let useGhInstead = "Use the GitHub CLI (`gh`) instead"

    /// `useGhInstead`'s hover help.
    public static let useGhInsteadHelp = "Shipyard reuses the `gh` command's sign-in if you already use it."

    /// The install hint's hover help (the ⓘ beside the `gh` way).
    public static let installGhHelp = "How to install `gh`"

    /// The install hint's popover: where to get `gh`, before `brewInstallGh`
    /// in a copyable box. Markdown, so the link is clickable.
    public static let installGh = "Download it from [cli.github.com](https://cli.github.com), or run:"

    /// The Homebrew command that installs `gh`.
    public static let brewInstallGh = "brew install gh"

    /// Shown while `start()` looks for a token, before there's a reason to show.
    public static let connecting = "Connecting to GitHub…"

    /// The device flow's button on the connect screen.
    public static let signInWithGitHub = "Sign in with GitHub"

    /// Why Sign in with GitHub is off: the build's OAuth App client ID is
    /// the placeholder.
    public static let signInUnavailable = "Not available in this build: it has no OAuth App client ID."

    /// The code screen's button that stops the device flow.
    public static let cancelSignIn = "Cancel"

    /// Said beside Connect with gh when it left shipyard signed out, for
    /// `reason` as it stands after the try, so the click doesn't look like
    /// it did nothing.
    public static func stillSignedOut(_ reason: Shipyard.SignedOutReason) -> String {
        switch reason {
        case .noToken: "The `gh` command still isn't signed in."
        case .rejected(.gh): "GitHub still rejects the `gh` command's sign-in."
        case .rejected(.tokenStore): "GitHub still rejects the sign-in."
        case .userSignedOut: "Still not connected."
        }
    }

    /// The connect screen for why shipyard is signed out. With `canSignIn`
    /// (the build has an OAuth App client ID) Sign in with GitHub leads,
    /// except where `gh` is the quicker fix: `gh` still signed in, or `gh`'s
    /// token rejected. Without, `gh` always leads and the button says why
    /// it's unavailable.
    public static func connect(_ reason: Shipyard.SignedOutReason, canSignIn: Bool) -> Connect {
        let unavailable = canSignIn ? nil : signInUnavailable
        let signInOrGh: Connect.Lead = canSignIn ? .signIn : .ghCommand
        switch reason {
        case .noToken, .userSignedOut(.signedOut):
            return Connect(
                title: "Welcome to Shipyard",
                message: canSignIn
                    ? "Connect your GitHub account to see the pull requests your agents open."
                    : "Connect your GitHub account through the GitHub CLI (`gh`).",
                lead: signInOrGh,
                signInUnavailable: unavailable,
                showsInstallHint: true
            )
        case .userSignedOut(.ghStillSignedIn):
            return Connect(
                title: "Welcome back",
                message: "The GitHub CLI (`gh`) is already signed in on this Mac, so connecting takes one click."
                    + (canSignIn ? " Or sign in with GitHub, if you'd rather." : ""),
                lead: .connectWithGh,
                signInUnavailable: unavailable,
                showsInstallHint: false
            )
        case .rejected(.tokenStore):
            return Connect(
                title: "Welcome back",
                message: "Your GitHub sign-in expired or was revoked. Sign in again to pick up where you left off.",
                lead: signInOrGh,
                signInUnavailable: unavailable,
                // The `gh` way folds into the same disclosure as on first launch.
                showsInstallHint: canSignIn
            )
        case .rejected(.gh):
            return Connect(
                title: "Welcome back",
                message: "GitHub rejected the `gh` command's sign-in. Sign `gh` in again in a terminal, then connect.",
                lead: .ghCommand,
                signInUnavailable: unavailable,
                showsInstallHint: false
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
            copyCode: "Copy code",
            copyTitle: "Copy",
            copied: "Copied",
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
        case .unauthorized: "GitHub refused the sign-in. Try again, or use `gh`."
        case .rejected(let code): "GitHub refused the sign-in (\(code)). Try again, or use `gh`."
        case .http(let status): "GitHub answered with an error (HTTP \(status)). Try again."
        case .network: "GitHub couldn't be reached. Check the connection and try again."
        case .malformed: "GitHub's answer couldn't be read. Try again."
        }
    }
}
