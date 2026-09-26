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

// MARK: - Repositories

/// A repository group: every repository the signed-in account reaches one
/// way, named after GitHub's own affiliations. The three don't overlap, and
/// together they are every repository the account can reach.
public enum RepositoryGroup: String, CaseIterable, Hashable, Sendable {
    /// Repositories the account itself owns.
    case owned
    /// Repositories the account reaches through membership of an
    /// organization, directly or through one of its teams.
    case organizations
    /// Someone else's repositories that added the account as a collaborator.
    case collaborator
}

/// One entry of a project's `repositories` (ADR 0002): a single repository
/// (`owner/name`), everything under one owner (`owner/*`), or a repository
/// group (a bare word). The key it sits under says it's a repository, so a
/// group needs no symbol of its own; a `/` marks a repository.
public enum RepositorySelector: Hashable, Sendable, CustomStringConvertible {
    /// `owner/name`, as the file spells it. Always listed, archived or not.
    case repository(String)
    /// `owner/*`: every repository the user or organization `owner` owns.
    case owner(String)
    /// `owned`, `organizations` or `collaborator`.
    case group(RepositoryGroup)

    /// The selector as it's written in the file.
    public var description: String {
        switch self {
        case .repository(let slug): slug
        case .owner(let login): "\(login)/*"
        case .group(let group): group.rawValue
        }
    }

    /// The single repository it names, for `owner/name`; `nil` for a
    /// selector that's looked up.
    public var slug: String? {
        if case .repository(let slug) = self { return slug }
        return nil
    }

    /// The lookup that finds its repositories on GitHub; `nil` for a single
    /// repository, which needs none.
    public var lookup: RepositoryLookup? {
        switch self {
        case .repository: nil
        case .owner(let login): .owner(login.lowercased())
        case .group(let group): .group(group)
        }
    }

    /// Reads one entry of `repositories`, or says why it isn't one with a
    /// hint towards what was likely meant.
    public static func parse(_ text: String) throws(RepositorySelectorRejection) -> RepositorySelector {
        if let group = RepositoryGroup(rawValue: text) { return .group(group) }
        if text.hasPrefix("@") {
            let login = String(text.dropFirst())
            let hint = isLogin(login) ? "; for their repositories write `\(login)/*`" : ""
            throw RepositorySelectorRejection("`\(text)` is a login; `repositories` takes \(accepted)\(hint)")
        }
        if AuthorSelector.groups.contains(where: { $0.description == text }) {
            throw RepositorySelectorRejection("`\(text)` is an author group; `repositories` takes \(accepted)")
        }
        if text.contains("/") {
            if text.hasSuffix("/*") {
                let owner = String(text.dropLast(2))
                if isLogin(owner) { return .owner(owner) }
            } else if ConfigurationReader.isRepositorySlug(text) {
                return .repository(text)
            }
            throw RepositorySelectorRejection("repository `\(text)` isn't `owner/name` or `owner/*`")
        }
        let groups = RepositoryGroup.allCases.map(\.rawValue)
        if let near = Suggestion.nearest(to: text, in: groups) {
            throw RepositorySelectorRejection("unknown repository group `\(text)` (did you mean `\(near)`?)")
        }
        if isLogin(text) {
            throw RepositorySelectorRejection("unknown repository group `\(text)` (did you mean `\(text)/*`, or a repository as `\(text)/name`?)")
        }
        throw RepositorySelectorRejection("repository `\(text)` isn't \(accepted)")
    }

    /// What `repositories` takes, for the messages.
    static var accepted: String {
        let groups = RepositoryGroup.allCases.map { "`\($0.rawValue)`" }
        return "`owner/name`, `owner/*`, " + groups.dropLast().joined(separator: ", ") + " or " + groups.last!
    }

    /// An owner's login: a person's or an organization's, never a bot's.
    static func isLogin(_ text: String) -> Bool {
        AuthorSelector.isLogin(text) && !text.hasSuffix("[bot]")
    }
}

extension RepositorySelector: ExpressibleByStringLiteral {
    /// A selector written in code, such as a preset's `"owned"`; it must parse.
    public init(stringLiteral text: String) {
        do {
            self = try Self.parse(text)
        } catch {
            preconditionFailure("`\(text)` isn't a repository selector: \(error.message)")
        }
    }
}

/// Why an entry of `repositories` isn't a repository selector; `message`
/// is what the banner says after the line.
public struct RepositorySelectorRejection: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// What the repository resolver asks GitHub to list: a repository group of
/// the signed-in account, or everything one owner owns (login lowercased,
/// since logins aren't case-sensitive).
public enum RepositoryLookup: Hashable, Sendable {
    case group(RepositoryGroup)
    case owner(String)
}
