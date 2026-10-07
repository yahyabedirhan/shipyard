/// How shipyard is connected to GitHub while signed in: the account, once
/// GitHub has said which, and where the token came from. The GitHub view
/// shows it, and the settings menu marks GitHub while there is one.
public struct GitHubConnection: Equatable, Sendable {
    /// The account's login; `nil` while GitHub hasn't said (out of reach).
    public var login: String?
    public var source: TokenSource

    public init(login: String?, source: TokenSource) {
        self.login = login
        self.source = source
    }
}

extension Shipyard {
    /// The connection once signed in (the project picker or the projects);
    /// `nil` while signed out, while the device flow waits, and while
    /// `start()` still asks GitHub about the token it found.
    public var gitHubConnection: GitHubConnection? {
        guard let tokenSource else { return nil }
        switch phase {
        case .needsProjects, .ready: return GitHubConnection(login: viewer?.login, source: tokenSource)
        case .signedOut, .connecting: return nil
        }
    }
}
