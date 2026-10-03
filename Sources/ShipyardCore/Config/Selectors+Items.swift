import ShipyardConfig

// Matching an author or an item against the configuration's selectors is
// the app's (ADR 0006): ShipyardConfig parses the selectors, and only the
// app has items.

extension AuthorSelector {
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
}

extension AuthorFilter {
    public func includes(author: String, kind: AuthorKind, viewer: String?) -> Bool {
        let matches = { (selector: AuthorSelector) in selector.matches(author: author, kind: kind, viewer: viewer) }
        return (show.isEmpty || show.contains(where: matches)) && !hide.contains(where: matches)
    }

    public func includes(_ item: Item, viewer: String?) -> Bool {
        includes(author: item.author, kind: item.authorKind, viewer: viewer)
    }
}

extension NotificationRule {
    /// Whether the rule covers an item's author: any of its selectors
    /// matches, or it has none. A ping has no GitHub author, so a rule with
    /// `authors` never covers one.
    public func covers(_ item: Item, viewer: String?) -> Bool {
        if item.kind == .ping { return authors.isEmpty }
        return authors.isEmpty || authors.contains { $0.matches(item, viewer: viewer) }
    }
}
