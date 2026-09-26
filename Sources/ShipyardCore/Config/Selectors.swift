import Foundation

// Selectors name authors and repositories in the configuration (ADR 0002):
// a bare word is a group, `@` marks a login and `/` a repository. The key a
// selector sits under says which set it's from, so a group needs no symbol.

/// One entry of an author filter: an author group or a single login.
///
/// `me` is the signed-in account, so agents working as the user count as
/// `me`; `bots` is a GitHub Bot account or a login ending in `[bot]`;
/// `others` is everyone else. The three together cover every author once.
/// `matches` is the only author match in the codebase.
public enum AuthorSelector: Hashable, Sendable, CustomStringConvertible {
    case me
    case others
    case bots
    /// A login, written `@login` in the file and kept here without the `@`.
    case login(String)

    /// The author groups, in the order the file's documentation lists them.
    public static let groups: [AuthorSelector] = [.me, .others, .bots]

    /// The repository groups: bare words that belong under `repositories`,
    /// named here so an author filter can say where they go.
    static let repositoryGroups = ["owned", "organizations", "collaborator", "anywhere"]

    /// Why a string isn't an author selector, in the words the banner shows.
    public struct Rejection: Error, Equatable, Sendable {
        public var message: String
        public init(_ message: String) { self.message = message }
    }

    /// Reads a selector as the file writes it: `me`, `others`, `bots` or
    /// `@login`. A bare word that isn't a group, a repository group and a
    /// repository are rejected, each with a hint.
    public init(parsing text: String) throws(Rejection) {
        if let group = Self.groups.first(where: { $0.description == text }) {
            self = group
            return
        }
        if text.hasPrefix("@") {
            let login = String(text.dropFirst())
            guard Self.isLogin(login) else { throw Rejection("`\(text)` isn't followed by a GitHub login") }
            self = .login(login)
            return
        }
        let takes = "`authors` takes `me`, `others`, `bots` or an `@login`"
        if text.contains("/") { throw Rejection("`\(text)` is a repository; \(takes)") }
        if Self.repositoryGroups.contains(text) { throw Rejection("`\(text)` is a repository group; \(takes)") }
        if text == "any" { throw Rejection("unknown author `any` (an empty list means everyone)") }
        guard Self.isLogin(text) else {
            throw Rejection("unknown author `\(text)` (expected `me`, `others`, `bots` or an `@login`)")
        }
        let group = Suggestion.nearest(to: text, in: Self.groups.map(\.description))
        let hint = group.map { "did you mean `\($0)` or `@\(text)`?" } ?? "did you mean `@\(text)`?"
        throw Rejection("unknown author `\(text)` (\(hint))")
    }

    /// As the file writes it: the group's name, or `@login`.
    public var description: String {
        switch self {
        case .me: "me"
        case .others: "others"
        case .bots: "bots"
        case .login(let login): "@" + login
        }
    }

    /// Whether this selector covers an author. `viewer` is the signed-in
    /// login, when known; an author the fetch already marked `.me` is the
    /// viewer too. Logins match ignoring case, as GitHub's do.
    public func matches(author: String, kind: AuthorKind, viewer: String?) -> Bool {
        let author = author.lowercased()
        let isBot = kind == .bot || author.hasSuffix("[bot]")
        let isMe = !isBot && (kind == .me || viewer.map { $0.lowercased() == author } ?? false)
        switch self {
        case .me: return isMe
        case .bots: return isBot
        case .others: return !isMe && !isBot
        case .login(let login): return login.lowercased() == author
        }
    }

    public func matches(_ item: Item, viewer: String?) -> Bool {
        matches(author: item.author, kind: item.authorKind, viewer: viewer)
    }

    /// A GitHub login: letters, digits and hyphens, starting with a letter
    /// or digit; a bot's keeps GitHub's `[bot]` suffix.
    static func isLogin(_ text: String) -> Bool {
        let name = text.hasSuffix("[bot]") ? String(text.dropLast("[bot]".count)) : text
        guard let first = name.unicodeScalars.first, first != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-": true
            default: false
            }
        }
    }
}

/// Whose items a kind lists: `show` minus `hide`. An empty `show` is
/// everyone, and `hide` wins over `show`.
public struct AuthorFilter: Equatable, Sendable {
    public var show: [AuthorSelector]
    public var hide: [AuthorSelector]

    public init(show: [AuthorSelector] = [], hide: [AuthorSelector] = []) {
        self.show = show
        self.hide = hide
    }

    public func includes(author: String, kind: AuthorKind, viewer: String?) -> Bool {
        let matches = { (selector: AuthorSelector) in selector.matches(author: author, kind: kind, viewer: viewer) }
        return (show.isEmpty || show.contains(where: matches)) && !hide.contains(where: matches)
    }

    public func includes(_ item: Item, viewer: String?) -> Bool {
        includes(author: item.author, kind: item.authorKind, viewer: viewer)
    }
}

/// The `authors` keys a table sets; unset keys keep the value below, so a
/// project's `authors = { hide = [...] }` keeps the default `show`.
public struct AuthorFilterOverrides: Equatable, Sendable {
    public var show: [AuthorSelector]?
    public var hide: [AuthorSelector]?

    public init(show: [AuthorSelector]? = nil, hide: [AuthorSelector]? = nil) {
        self.show = show
        self.hide = hide
    }

    public func applied(to base: AuthorFilter) -> AuthorFilter {
        AuthorFilter(show: show ?? base.show, hide: hide ?? base.hide)
    }
}
