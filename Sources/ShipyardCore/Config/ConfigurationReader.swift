import Foundation
import TOMLDecoder

extension Configuration {
    /// A valid configuration and the warnings found on the way (unknown keys).
    public struct Decoded: Equatable, Sendable {
        public var configuration: Configuration
        public var warnings: [ConfigIssue]

        public init(configuration: Configuration, warnings: [ConfigIssue] = []) {
            self.configuration = configuration
            self.warnings = warnings
        }
    }

    /// Reads and validates `config.toml`. Empty data is the default
    /// configuration with no projects.
    public static func decode(_ data: Data) throws(ConfigError) -> Decoded {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError([ConfigIssue(line: nil, message: "the file isn't UTF-8 text")])
        }
        return try decode(text)
    }

    /// Reads and validates the text of `config.toml`.
    ///
    /// Rejects, with a line and a message: invalid TOML, a value of the wrong
    /// type, an unknown choice (event, author filter, count style…) with the
    /// nearest valid one suggested, a repository that isn't `owner/name`,
    /// duplicate project names, negative windows, an interval under 30 s, a
    /// rate-limit share outside 1–50 and an unsupported `version`. Unknown
    /// keys are warnings, so a newer file doesn't break an older app.
    public static func decode(_ text: String) throws(ConfigError) -> Decoded {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            throw ConfigError([ConfigIssue(invalidTOML: error)])
        }
        let reader = ConfigurationReader(map: TOMLSourceMap(text))
        let configuration = reader.configuration(from: root)
        if !reader.errors.isEmpty { throw ConfigError(reader.errors) }
        return Decoded(configuration: configuration, warnings: reader.warnings)
    }
}

extension ConfigIssue {
    /// TOMLDecoder's parse errors carry the line only in their description,
    /// as "(Line 3) Syntax error: …".
    init(invalidTOML error: any Error) {
        let (line, detail) = Self.splitLine(from: String(describing: error))
        self.init(line: line, message: "invalid TOML: \(detail)")
    }

    static func splitLine(from description: String) -> (Int?, String) {
        guard description.hasPrefix("(Line "),
              let close = description.firstIndex(of: ")"),
              let line = Int(description[description.index(description.startIndex, offsetBy: 6)..<close])
        else { return (nil, description) }
        let rest = description[description.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (line, rest)
    }
}

/// Walks the parsed document key by key, filling a `Configuration`,
/// collecting errors (which reject the file) and warnings (which don't).
final class ConfigurationReader {
    private let map: TOMLSourceMap
    private(set) var errors: [ConfigIssue] = []
    private(set) var warnings: [ConfigIssue] = []

    init(map: TOMLSourceMap) { self.map = map }

    /// A table and where it sits in the file.
    struct Node {
        let table: TOMLTable
        let path: ConfigPath
    }

    // MARK: The file's shape

    func configuration(from root: TOMLTable) -> Configuration {
        let node = Node(table: root, path: [])
        var config = Configuration()
        warnUnknownKeys(in: node, known: [
            "version", "refresh-interval-seconds", "launch-at-login", "hide-authors",
            "menu-bar", "menu", "rate-limit", "attention", "defaults", "projects",
        ])

        if let version = int(node, "version") {
            if version == Configuration.supportedVersion {
                config.version = version
            } else {
                error("`version` \(version) isn't supported; this shipyard reads version \(Configuration.supportedVersion)", at: node.path + [.key("version")])
            }
        }
        if let interval = int(node, "refresh-interval-seconds") {
            if interval < 30 {
                error("`refresh-interval-seconds` must be at least 30 (got \(interval))", at: node.path + [.key("refresh-interval-seconds")])
            } else {
                config.refreshIntervalSeconds = interval
            }
        }
        if let value = bool(node, "launch-at-login") { config.launchAtLogin = value }
        let hiddenAuthors = strings(node, "hide-authors")

        if let menuBar = table(node, "menu-bar") {
            warnUnknownKeys(in: menuBar, known: ["count"])
            if let count = choice(menuBar, "count", MenuBarCount.self) { config.menuBar.count = count }
        }

        if let menu = table(node, "menu") {
            warnUnknownKeys(in: menu, known: ["layout"])
            if let layout = choice(menu, "layout", MenuLayout.self) { config.menu.layout = layout }
        }

        if let rateLimit = table(node, "rate-limit") {
            warnUnknownKeys(in: rateLimit, known: ["show", "max-share-percent"])
            if let show = choice(rateLimit, "show", RateLimitDisplay.self) { config.rateLimit.show = show }
            if let share = int(rateLimit, "max-share-percent") {
                if (1...50).contains(share) {
                    config.rateLimit.maxSharePercent = share
                } else {
                    error("`max-share-percent` must be between 1 and 50 (got \(share))", at: rateLimit.path + [.key("max-share-percent")])
                }
            }
        }

        if let attention = table(node, "attention") {
            warnUnknownKeys(in: attention, known: ["unseen", "changed", "review-requested", "checks-failed"])
            if let value = bool(attention, "unseen") { config.attention.unseen = value }
            if let value = bool(attention, "changed") { config.attention.changed = value }
            if let value = bool(attention, "review-requested") { config.attention.reviewRequested = value }
            if let value = bool(attention, "checks-failed") { config.attention.checksFailed = value }
        }

        if let defaults = table(node, "defaults") {
            warnUnknownKeys(in: defaults, known: ["pull-requests", "issues", "workflow-runs", "notifications", "archived", "forks"] + Self.arrangementKeys)
            if let value = bool(defaults, "archived") { config.defaults.archived = value }
            if let value = bool(defaults, "forks") { config.defaults.forks = value }
            config.defaults.pullRequests = pullRequests(defaults).applied(to: config.defaults.pullRequests)
            config.defaults.issues = issues(defaults).applied(to: config.defaults.issues)
            config.defaults.workflowRuns = workflowRuns(defaults).applied(to: config.defaults.workflowRuns)
            if let rules = notifications(defaults) { config.defaults.notifications = rules }
            config.defaults.arrangement = arrangement(defaults).applied(to: config.defaults.arrangement)
        }
        if let hiddenAuthors { readHideAuthors(hiddenAuthors, into: &config.defaults, at: node.path + [.key("hide-authors")]) }

        if let projects = tables(node, "projects") {
            config.projects = projects.compactMap { project($0, defaults: config.defaults) }
            rejectDuplicateNames(projects)
        }
        return config
    }

    private func project(_ node: Node, defaults: Configuration.Defaults) -> Configuration.Project? {
        warnUnknownKeys(in: node, known: [
            "name", "repositories", "pull-requests", "issues", "workflow-runs", "notifications", "archived", "forks",
        ] + Self.arrangementKeys)
        let name = string(node, "name")
        let repositories = strings(node, "repositories")
        if name == nil && !node.table.contains(key: "name") {
            error("a project needs a `name`", at: node.path)
        } else if let name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            error("a project's `name` can't be empty", at: node.path + [.key("name")])
        }
        if repositories == nil && !node.table.contains(key: "repositories") {
            error("project `\(name ?? "")` needs `repositories`, a list of repositories (`owner/name`, `owner/*` or a group such as `owned`)", at: node.path)
        } else if let repositories, repositories.isEmpty {
            error("project `\(name ?? "")` needs at least one repository", at: node.path + [.key("repositories")])
        }
        var listed = Set<String>()
        var spelled: [String: Int] = [:]
        var selectors: [RepositorySelector] = []
        for repository in repositories ?? [] {
            // Which appearance of this exact spelling it is, to find its line.
            let occurrence = spelled[repository, default: 0]
            spelled[repository] = occurrence + 1
            let line = map.line(for: node.path + [.key("repositories")], value: repository, occurrence: occurrence)
            do {
                let selector = try RepositorySelector.parse(repository)
                selectors.append(selector)
                // GitHub's names aren't case-sensitive: `o/r` and `O/R` are one repository.
                if !listed.insert(repository.lowercased()).inserted {
                    errors.append(ConfigIssue(line: line, message: Self.duplicateRepositoryMessage(repository, project: name ?? "")))
                }
            } catch {
                errors.append(ConfigIssue(line: line, message: error.message))
            }
        }
        guard let name, repositories != nil else { return nil }
        let project = Configuration.Project(
            name: name,
            repositories: selectors,
            pullRequests: pullRequests(node),
            issues: issues(node),
            workflowRuns: workflowRuns(node),
            notifications: notifications(node),
            arrangement: arrangement(node),
            archived: bool(node, "archived"),
            forks: bool(node, "forks")
        )
        if selectors.contains(.anywhere), !Self.allowsAnywhere(project, defaults: defaults) {
            let line = map.line(for: node.path + [.key("repositories")], value: RepositorySelector.anywhereName, occurrence: 0)
            errors.append(ConfigIssue(line: line, message: Self.anywhereMessage))
        }
        return project
    }

    /// `anywhere` finds only pull requests waiting on the user, so a project
    /// using it must list exactly those: pull requests shown with
    /// `review-requested = true` (in the project or its defaults), and no
    /// issues or runs.
    private static func allowsAnywhere(_ project: Configuration.Project, defaults: Configuration.Defaults) -> Bool {
        let pullRequests = project.pullRequests.applied(to: defaults.pullRequests)
        return pullRequests.show && pullRequests.reviewRequested
            && !project.issues.applied(to: defaults.issues).show
            && !project.workflowRuns.applied(to: defaults.workflowRuns).show
    }

    static let anywhereMessage = "`anywhere` needs `pull-requests = { review-requested = true }`, and lists no issues or runs"

    /// The keys that arrange a project, written straight under `[defaults]`
    /// or in a `[[projects]]` block.
    static let arrangementKeys = ["group-by", "subsections", "sort-by"]

    private func arrangement(_ node: Node) -> ArrangementOverrides {
        ArrangementOverrides(
            groupBy: choice(node, "group-by", GroupBy.self),
            subsections: bool(node, "subsections"),
            sortBy: choice(node, "sort-by", SortBy.self)
        )
    }

    private func pullRequests(_ parent: Node) -> PullRequestOverrides {
        guard let node = table(parent, "pull-requests") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "closed-window-days", "drafts", "authors", "review-requested"])
        return PullRequestOverrides(
            show: bool(node, "show"),
            states: states(node, of: .pullRequest),
            closedWindowDays: window(node, "closed-window-days"),
            drafts: bool(node, "drafts"),
            authors: authorFilter(node),
            reviewRequested: bool(node, "review-requested")
        )
    }

    private func issues(_ parent: Node) -> IssueOverrides {
        guard let node = table(parent, "issues") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "closed-window-days", "authors"])
        return IssueOverrides(
            show: bool(node, "show"),
            states: states(node, of: .issue),
            closedWindowDays: window(node, "closed-window-days"),
            authors: authorFilter(node)
        )
    }

    private func workflowRuns(_ parent: Node) -> WorkflowRunOverrides {
        guard let node = table(parent, "workflow-runs") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "finished-window-hours", "branches", "authors"])
        return WorkflowRunOverrides(
            show: bool(node, "show"),
            states: states(node, of: .workflowRun),
            finishedWindowHours: window(node, "finished-window-hours"),
            branches: choice(node, "branches", WorkflowRunBranches.self),
            authors: authorFilter(node)
        )
    }

    /// A kind's `states`: a list of the states that kind takes. Each one it
    /// doesn't take is an error on its own line, with the nearest one it
    /// does take suggested.
    private func states(_ node: Node, of kind: ItemKind) -> Set<StateGroup>? {
        guard let texts = strings(node, "states") else { return nil }
        let valid = StateGroup.all(for: kind).map(\.rawValue)
        var states: Set<StateGroup> = []
        var readable = true
        for text in texts {
            if valid.contains(text), let state = StateGroup(rawValue: text) {
                states.insert(state)
                continue
            }
            let hint = Suggestion.nearest(to: text, in: valid).map { "did you mean `\($0)`?" }
                ?? "expected " + valid.map { "`\($0)`" }.joined(separator: ", ")
            error("unknown \(kind.noun) state `\(text)` (\(hint))", at: node.path + [.key("states")], value: text)
            readable = false
        }
        return readable ? states : nil
    }

    /// A kind's `authors = { show = [...], hide = [...] }`.
    private func authorFilter(_ parent: Node) -> AuthorFilterOverrides {
        guard let node = table(parent, "authors") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "hide"])
        return AuthorFilterOverrides(show: authorSelectors(node, "show"), hide: authorSelectors(node, "hide"))
    }

    /// The old top-level `hide-authors`, a list of bare logins, read as a
    /// `hide` of those logins in each kind's defaults, with a warning.
    private func readHideAuthors(_ logins: [String], into defaults: inout Configuration.Defaults, at path: ConfigPath) {
        let selectors = logins.map { AuthorSelector.login($0.hasPrefix("@") ? String($0.dropFirst()) : $0) }
        defaults.pullRequests.authors.hide += selectors
        defaults.issues.authors.hide += selectors
        defaults.workflowRuns.authors.hide += selectors
        let written = selectors.map { Configuration.tomlString($0.description) }.joined(separator: ", ")
        warnings.append(ConfigIssue(
            line: map.line(for: path),
            message: "`hide-authors` is the old form: it's read as `authors = { hide = [\(written)] }` "
                + "in `[defaults.pull-requests]`, `[defaults.issues]` and `[defaults.workflow-runs]`; write that instead"
        ))
    }

    private func notifications(_ parent: Node) -> [NotificationRule]? {
        guard let rules = tables(parent, "notifications") else { return nil }
        return rules.compactMap { node in
            warnUnknownKeys(in: node, known: ["event", "authors"])
            let authors = ruleAuthors(node)
            guard node.table.contains(key: "event") else {
                error("a notification rule needs an `event`", at: node.path)
                return nil
            }
            guard let event = choice(node, "event", EventKind.self, noun: "event") else { return nil }
            return NotificationRule(event: event, authors: authors ?? [])
        }
    }

    /// A rule's `authors`: a list of author selectors, or one of the old
    /// strings (`"any"`, `"me"`, `"others"`, `"bots"`), read with a warning.
    private func ruleAuthors(_ node: Node) -> [AuthorSelector]? {
        guard let old = try? node.table.string(forKey: "authors") else { return authorSelectors(node, "authors") }
        let path = node.path + [.key("authors")]
        guard NotificationRule.legacyAuthors.contains(old) else {
            do throws(AuthorSelector.Rejection) {
                let selector = try AuthorSelector(parsing: old)
                error("`authors` is a list: write `authors = [\(Configuration.tomlString(selector.description))]`", at: path, value: old)
            } catch {
                self.error(error.message, at: path, value: old)
            }
            return nil
        }
        let selectors = old == "any" ? [] : [try! AuthorSelector(parsing: old)]
        let written = "[" + selectors.map { Configuration.tomlString($0.description) }.joined(separator: ", ") + "]"
        let advice = old == "any" ? "write `authors = []`, or leave it out, for everyone" : "write `authors = \(written)`"
        warnings.append(ConfigIssue(
            line: map.line(for: path, value: old),
            message: "`authors = \"\(old)\"` is the old form of a notification rule's authors; \(advice)"
        ))
        return selectors
    }

    /// A list of author selectors; each one that doesn't read is an error
    /// on its own line.
    private func authorSelectors(_ node: Node, _ key: String) -> [AuthorSelector]? {
        guard let texts = strings(node, key) else { return nil }
        var selectors: [AuthorSelector] = []
        var valid = true
        for text in texts {
            do throws(AuthorSelector.Rejection) {
                selectors.append(try AuthorSelector(parsing: text))
            } catch {
                self.error(error.message, at: node.path + [.key(key)], value: text)
                valid = false
            }
        }
        return valid ? selectors : nil
    }

    /// A window in days or hours: a whole number, 0 or more.
    private func window(_ node: Node, _ key: String) -> Int? {
        guard let value = int(node, key) else { return nil }
        guard value >= 0 else {
            error("`\(key)` can't be negative (got \(value))", at: node.path + [.key(key)])
            return nil
        }
        return value
    }

    private func rejectDuplicateNames(_ nodes: [Node]) {
        var firstLine: [String: Int?] = [:]
        for node in nodes {
            guard let name = try? node.table.string(forKey: "name") else { continue }
            let line = map.line(for: node.path + [.key("name")])
            if let first = firstLine[name] {
                let earlier = first.map { " (first on line \($0))" } ?? ""
                errors.append(ConfigIssue(line: line, message: "project name `\(name)` is used twice\(earlier)"))
            } else {
                firstLine[name] = .some(line)
            }
        }
    }

    /// Why a project can't list `repository` again (in any letter case).
    static func duplicateRepositoryMessage(_ repository: String, project: String) -> String {
        "project `\(project)` lists repository `\(repository)` twice (names aren't case-sensitive)"
    }

    /// `owner/name`: a GitHub login (letters, digits, hyphens) and a
    /// repository name (letters, digits, `-`, `_`, `.`).
    static func isRepositorySlug(_ slug: String) -> Bool {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let owner = parts[0], name = parts[1]
        let ownerOK = !owner.isEmpty && owner.unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" }
        let nameOK = !name.isEmpty && name != "." && name != ".."
            && name.unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" || $0 == "_" || $0 == "." }
        return ownerOK && nameOK
    }

    // MARK: Typed reads
    //
    // Each returns nil when the key is absent, and records an error (and
    // returns nil) when it's present with the wrong type.

    private func int(_ node: Node, _ key: String) -> Int? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return try Int(clamping: node.table.integer(forKey: key))
        } catch {
            typeError(node, key, expected: "a whole number", error)
            return nil
        }
    }

    private func bool(_ node: Node, _ key: String) -> Bool? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return try node.table.bool(forKey: key)
        } catch {
            typeError(node, key, expected: "true or false", error)
            return nil
        }
    }

    private func string(_ node: Node, _ key: String) -> String? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return try node.table.string(forKey: key)
        } catch {
            typeError(node, key, expected: "a string", error)
            return nil
        }
    }

    private func strings(_ node: Node, _ key: String) -> [String]? {
        guard node.table.contains(key: key) else { return nil }
        let array: TOMLArray
        do {
            array = try node.table.array(forKey: key)
        } catch {
            typeError(node, key, expected: "a list of strings", error)
            return nil
        }
        var values: [String] = []
        for index in 0..<array.count {
            do {
                values.append(try array.string(atIndex: index))
            } catch {
                typeError(node, key, expected: "a list of strings", error)
                return nil
            }
        }
        return values
    }

    private func table(_ node: Node, _ key: String) -> Node? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return Node(table: try node.table.table(forKey: key), path: node.path + [.key(key)])
        } catch {
            typeError(node, key, expected: "a table", error)
            return nil
        }
    }

    /// An array of tables, written as `[[key]]` blocks or as `key = [{…}, …]`.
    private func tables(_ node: Node, _ key: String) -> [Node]? {
        guard node.table.contains(key: key) else { return nil }
        let array: TOMLArray
        do {
            array = try node.table.array(forKey: key)
        } catch {
            typeError(node, key, expected: "a list of tables (`[[\((node.path + [.key(key)]).dotted)]]` blocks)", error)
            return nil
        }
        var nodes: [Node] = []
        for index in 0..<array.count {
            do {
                nodes.append(Node(table: try array.table(atIndex: index), path: node.path + [.key(key), .index(index)]))
            } catch {
                typeError(node, key, expected: "a list of tables", error)
                return nil
            }
        }
        return nodes
    }

    /// A string that must be one of `T`'s values; a near miss is suggested.
    private func choice<T: CaseIterable & RawRepresentable>(
        _ node: Node, _ key: String, _ type: T.Type, noun: String = "value"
    ) -> T? where T.RawValue == String {
        guard let raw = string(node, key) else { return nil }
        if let value = T(rawValue: raw) { return value }
        let valid = T.allCases.map(\.rawValue)
        let hint = Suggestion.nearest(to: raw, in: valid).map { "did you mean `\($0)`?" }
            ?? "expected one of " + valid.map { "`\($0)`" }.joined(separator: ", ")
        let what = noun == "value" ? "value `\(raw)` for `\(key)`" : "\(noun) `\(raw)`"
        error("unknown \(what) (\(hint))", at: node.path + [.key(key)], value: raw)
        return nil
    }

    // MARK: Recording

    private func warnUnknownKeys(in node: Node, known: [String]) {
        for key in node.table.keys where !known.contains(key) {
            let path = node.path + [.key(key)]
            let hint = Suggestion.nearest(to: key, in: known).map { "; did you mean `\($0)`?" } ?? ""
            warnings.append(ConfigIssue(line: map.line(for: path), message: "unknown setting `\(path.dotted)` (ignored\(hint))"))
        }
    }

    private func typeError(_ node: Node, _ key: String, expected: String, _ underlying: any Error) {
        let path = node.path + [.key(key)]
        let (tomlLine, _) = ConfigIssue.splitLine(from: String(describing: underlying))
        errors.append(ConfigIssue(line: tomlLine ?? map.line(for: path), message: "`\(path.dotted)` must be \(expected)"))
    }

    private func error(_ message: String, at path: ConfigPath, value: String? = nil) {
        errors.append(ConfigIssue(line: map.line(for: path, value: value), message: message))
    }
}

/// Picks the valid value a misspelt one most likely meant.
enum Suggestion {
    /// The closest candidate, if it's close enough to be a plausible typo:
    /// the same letters ignoring case and `-`/`_`, or within an edit
    /// distance of about a third of its length (at least 2).
    static func nearest(to input: String, in candidates: [String]) -> String? {
        let normalized = normalize(input)
        if let same = candidates.first(where: { normalize($0) == normalized }) { return same }
        let scored = candidates.map { ($0, distance(input.lowercased(), $0.lowercased())) }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        return best.1 <= max(2, best.0.count / 3) ? best.0 : nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0 != "-" && $0 != "_" }
    }

    /// Levenshtein distance.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

private extension ItemKind {
    /// The kind as a state's message names it: "unknown issue state …".
    var noun: String {
        switch self {
        case .pullRequest: "pull request"
        case .issue: "issue"
        case .workflowRun: "workflow run"
        }
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        switch self {
        case "A"..."Z", "a"..."z", "0"..."9": true
        default: false
        }
    }
}
