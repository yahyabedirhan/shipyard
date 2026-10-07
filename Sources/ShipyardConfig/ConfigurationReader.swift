import Foundation
import ShipyardCommand
import TOMLDecoder

extension Configuration {
    /// A valid configuration and the warnings found on the way (unknown keys).
    public struct Decoded: Equatable, Sendable {
        public var configuration: Configuration
        public var warnings: [ConfigurationIssue]

        public init(configuration: Configuration, warnings: [ConfigurationIssue] = []) {
            self.configuration = configuration
            self.warnings = warnings
        }
    }

    /// Reads and validates `config.toml`. Empty data is the default
    /// configuration with no projects.
    public static func decode(_ data: Data) throws(ConfigurationError) -> Decoded {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigurationError([ConfigurationIssue(line: nil, message: "the file isn't UTF-8 text")])
        }
        return try decode(text)
    }

    /// Reads and validates the text of `config.toml`.
    ///
    /// Rejects, with a line and a message: invalid TOML, a value of the wrong
    /// type, an unknown choice (event, author filter, count style…) with the
    /// nearest valid one suggested, a repository that isn't `owner/name`,
    /// a project slug that isn't one or is used twice, negative windows, an
    /// interval under 30 s, a rate-limit share outside 1–50 and an
    /// unsupported `version`. Unknown keys are warnings, so a newer file
    /// doesn't break an older app; so are old keys (read as their new
    /// form) and a file that sets keys without `version`.
    public static func decode(_ text: String) throws(ConfigurationError) -> Decoded {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            throw ConfigurationError([ConfigurationIssue(invalidTOML: error)])
        }
        let reader = ConfigurationReader(map: TOMLSourceMap(text))
        let configuration = reader.configuration(from: root)
        if !reader.errors.isEmpty { throw ConfigurationError(reader.errors) }
        return Decoded(configuration: configuration, warnings: reader.warnings)
    }
}

extension ConfigurationIssue {
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
    private(set) var errors: [ConfigurationIssue] = []
    private(set) var warnings: [ConfigurationIssue] = []

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
            "version", "refresh-interval", "launch-at-login", "hide-authors",
            "menu-bar", "menu", "rate-limit", "attention", "herdr", "remote", "notices", "banners", "defaults", "projects",
        ], old: ["refresh-interval-seconds"])

        if let version = int(node, "version") {
            if version == Configuration.supportedVersion {
                config.version = version
            } else {
                error("`version` \(version) isn't supported; this shipyard reads version \(Configuration.supportedVersion)", at: node.path + [.key("version")])
            }
        } else if !node.table.contains(key: "version"), !node.table.keys.isEmpty {
            warnings.append(ConfigurationIssue(line: nil, message: Self.missingVersionMessage))
        }
        if let interval = duration(node, "refresh-interval", old: "refresh-interval-seconds", unit: "s") {
            if interval < Self.shortestRefreshInterval {
                // Named as the file sets it: the new key's text, else the old key's number.
                if let text = try? node.table.string(forKey: "refresh-interval") {
                    error("`refresh-interval` must be at least \"30s\" (got \(Configuration.tomlString(text)))", at: node.path + [.key("refresh-interval")])
                } else {
                    error("`refresh-interval-seconds` must be at least 30 (got \(Int(interval)))", at: node.path + [.key("refresh-interval-seconds")])
                }
            } else {
                config.refreshInterval = interval
            }
        }
        if let value = bool(node, "launch-at-login") { config.launchAtLogin = value }
        let hiddenAuthors = strings(node, "hide-authors")

        if let menuBar = table(node, "menu-bar") {
            warnUnknownKeys(in: menuBar, known: ["count"])
            if let count = choice(menuBar, "count", MenuBarCount.self) { config.menuBar.count = count }
        }

        if let menu = table(node, "menu") {
            warnUnknownKeys(in: menu, known: ["layout", "header-counts"])
            if let layout = choice(menu, "layout", MenuLayout.self) { config.menu.layout = layout }
            if let kinds = headerCounts(menu) { config.menu.headerCounts = kinds }
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

        if let herdr = table(node, "herdr") {
            warnUnknownKeys(in: herdr, known: ["terminal"])
            if let terminal = string(herdr, "terminal") {
                let app = terminal.trimmingCharacters(in: .whitespaces)
                if app.isEmpty {
                    error("`terminal` names your terminal app, by name or bundle id; leave it out to only focus the tab", at: herdr.path + [.key("terminal")])
                } else {
                    config.herdr.terminal = app
                }
            }
        }

        if let remote = table(node, "remote") {
            warnUnknownKeys(in: remote, known: ["machines"])
            if let machines = strings(remote, "machines") {
                config.remote.machines = readMachines(machines, at: remote.path + [.key("machines")])
            }
        }

        if let notices = table(node, "notices") {
            warnUnknownKeys(in: notices, known: ["listen", "port"])
            if let value = bool(notices, "listen") { config.notices.listen = value }
            if let port = int(notices, "port") {
                if NoticePort.range.contains(port) {
                    config.notices.port = port
                } else {
                    error("`port` must be between \(NoticePort.range.lowerBound) and \(NoticePort.range.upperBound) (got \(port))", at: notices.path + [.key("port")])
                }
            }
        }

        if let banners = table(node, "banners") {
            warnUnknownKeys(in: banners, known: ["snooze-duration"], old: ["snooze"])
            if let snooze = duration(banners, "snooze-duration", renamedFrom: "snooze") {
                if snooze > 0 {
                    config.banners.snoozeDuration = snooze
                } else {
                    let key = banners.table.contains(key: "snooze-duration") ? "snooze-duration" : "snooze"
                    error("`\(key)` must be longer than 0, such as \"1h\" or \"10s\"", at: banners.path + [.key(key)])
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
            warnUnknownKeys(in: defaults, known: ["pull-requests", "issues", "workflow-runs", "pings", "notes", "notifications", "archived", "forks"] + Self.arrangementKeys)
            if let value = bool(defaults, "archived") { config.defaults.archived = value }
            if let value = bool(defaults, "forks") { config.defaults.forks = value }
            config.defaults.pullRequests = pullRequests(defaults).applied(to: config.defaults.pullRequests)
            config.defaults.issues = issues(defaults).applied(to: config.defaults.issues)
            config.defaults.workflowRuns = workflowRuns(defaults).applied(to: config.defaults.workflowRuns)
            config.defaults.pings = pings(defaults).applied(to: config.defaults.pings)
            config.defaults.notes = notes(defaults).applied(to: config.defaults.notes)
            if let rules = notifications(defaults) { config.defaults.notifications = rules }
            config.defaults.arrangement = arrangement(defaults).applied(to: config.defaults.arrangement)
        }
        if let hiddenAuthors { readHideAuthors(hiddenAuthors, into: &config.defaults, at: node.path + [.key("hide-authors")]) }

        if let projects = tables(node, "projects") {
            var firstLine: [String: Int?] = [:]
            for node in projects {
                guard let project = project(node, defaults: config.defaults) else { continue }
                // The slug's line, or the old `name`'s it was made from.
                let line = map.line(for: node.path + [.key(node.table.contains(key: "slug") ? "slug" : "name")])
                if let first = firstLine[project.slug] {
                    let earlier = first.map { " (first on line \($0))" } ?? ""
                    errors.append(ConfigurationIssue(line: line, message: "project slug `\(project.slug)` is used twice\(earlier)"))
                } else {
                    firstLine[project.slug] = .some(line)
                    config.projects.append(project)
                }
            }
        }
        for label in config.remote.machines where config.projects.contains(where: { $0.slug == label || $0.title == label }) {
            error("`\(label)` is both a machine in `[remote] machines` and a project's slug or title; rename the project, since a machine's pings list under its label", at: [.key("remote"), .key("machines")])
        }
        return config
    }

    /// The warning for a file that sets keys without `version`.
    static let missingVersionMessage = "the file sets no `version`: add `version = \(Configuration.supportedVersion)` at the top; "
        + "from version 2, a file without it is an error"

    /// The shortest `refresh-interval`, in seconds.
    static let shortestRefreshInterval: TimeInterval = 30

    /// `[remote] machines`: Herdr labels, trimmed. A label that's empty,
    /// starts with `-` (it would read as a flag of `herdr`), holds a
    /// control character or comes twice is an error.
    private func readMachines(_ labels: [String], at path: ConfigPath) -> [String] {
        var machines: [String] = []
        for raw in labels {
            let label = raw.trimmingCharacters(in: .whitespaces)
            if label.isEmpty {
                error("a machine in `machines` is named by its Herdr label, which can't be empty", at: path)
            } else if label.hasPrefix("-") {
                error("`\(label)` isn't a Herdr machine label: a label can't start with `-`", at: path)
            } else if label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                error("a Herdr machine label can't hold a control character", at: path)
            } else if machines.contains(label) {
                error("`\(label)` is listed twice in `machines`", at: path)
            } else {
                machines.append(label)
            }
        }
        return machines
    }

    private func project(_ node: Node, defaults: Configuration.Defaults) -> Configuration.Project? {
        warnUnknownKeys(in: node, known: [
            "slug", "title", "repositories", "pull-requests", "issues", "workflow-runs", "pings", "notes", "notifications", "archived", "forks",
        ] + Self.arrangementKeys, old: ["name"])
        let identity = projectIdentity(node)
        // How the messages below name the project.
        let name = identity?.slug ?? (try? node.table.string(forKey: "slug")) ?? (try? node.table.string(forKey: "name"))
        let repositories = strings(node, "repositories")
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
                    errors.append(ConfigurationIssue(line: line, message: Self.duplicateRepositoryMessage(repository, project: name ?? "")))
                }
            } catch {
                errors.append(ConfigurationIssue(line: line, message: error.message))
            }
        }
        guard let identity, repositories != nil else { return nil }
        let project = Configuration.Project(
            slug: identity.slug,
            title: identity.title,
            repositories: selectors,
            pullRequests: pullRequests(node),
            issues: issues(node),
            workflowRuns: workflowRuns(node),
            pings: pings(node),
            notes: notes(node),
            notifications: notifications(node, inProject: true),
            arrangement: arrangement(node),
            archived: bool(node, "archived"),
            forks: bool(node, "forks")
        )
        if selectors.contains(.anywhere), !Self.allowsAnywhere(project, defaults: defaults) {
            let line = map.line(for: node.path + [.key("repositories")], value: RepositorySelector.anywhereName, occurrence: 0)
            errors.append(ConfigurationIssue(line: line, message: Self.anywhereMessage))
        }
        return project
    }

    /// A project's `slug` and `title` (the slug when unset); `nil`, with
    /// the errors recorded, when they don't read. The old `name` still
    /// reads in their place, with a warning: its title is the name, and its
    /// slug the name made into one (`Configuration.slug(from:)`).
    private func projectIdentity(_ node: Node) -> (slug: String, title: String)? {
        if node.table.contains(key: "name") { return oldProjectName(node) }
        guard node.table.contains(key: "slug") else {
            error("a project needs a `slug`, its ID: lowercase letters and digits joined by single hyphens, such as \"e-commerce\"", at: node.path)
            return nil
        }
        guard let slug = string(node, "slug") else { return nil }
        let validSlug = slug.range(of: Configuration.slugPattern, options: .regularExpression) != nil
        if !validSlug {
            let suggestion = Configuration.slug(from: slug)
            let hint = suggestion.isEmpty ? "" : "; did you mean \(Configuration.tomlString(suggestion))?"
            error("`slug` must be lowercase letters and digits joined by single hyphens, such as \"e-commerce\" (got \(Configuration.tomlString(slug))\(hint))", at: node.path + [.key("slug")])
        }
        var title = slug
        if node.table.contains(key: "title") {
            guard let written = string(node, "title") else { return nil }
            if written.trimmingCharacters(in: .whitespaces).isEmpty {
                error("a project's `title` can't be empty; leave it out to show the slug", at: node.path + [.key("title")])
                return nil
            }
            title = written
        }
        return validSlug ? (slug, title) : nil
    }

    /// The old `name` of a project, as its slug and title, with a warning
    /// giving them; with `slug` or `title` beside it, an error on its line.
    private func oldProjectName(_ node: Node) -> (slug: String, title: String)? {
        let path = node.path + [.key("name")]
        if node.table.contains(key: "slug") || node.table.contains(key: "title") {
            error("`name` is the old form of `slug` and `title`, which this project sets too; delete `name`", at: path)
            return nil
        }
        guard let name = string(node, "name") else { return nil }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            error("a project's `name` can't be empty", at: path)
            return nil
        }
        let slug = Configuration.slug(from: name)
        if slug.isEmpty {
            error("`name` \(Configuration.tomlString(name)) has no letter or digit to make a `slug` of; write `slug` and `title` instead", at: path)
            return nil
        }
        let written = name == slug
            ? "`slug = \(Configuration.tomlString(slug))`; write that instead"
            : "`slug = \(Configuration.tomlString(slug))` and `title = \(Configuration.tomlString(name))`; write those instead"
        warnings.append(ConfigurationIssue(line: map.line(for: path), message: "`name` is the old form: it's read as \(written)"))
        return (slug, name)
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
    static let arrangementKeys = ["group-by", "subsections", "sort-by", "show-first"]

    private func arrangement(_ node: Node) -> ArrangementOverrides {
        ArrangementOverrides(
            groupBy: choice(node, "group-by", GroupBy.self),
            subsections: bool(node, "subsections"),
            sortBy: choice(node, "sort-by", SortBy.self),
            showFirst: window(node, "show-first")
        )
    }

    private func pullRequests(_ parent: Node) -> PullRequestOverrides {
        guard let node = table(parent, "pull-requests") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "closed-window", "closed-window-days", "drafts", "authors", "review-requested"])
        return PullRequestOverrides(
            show: bool(node, "show"),
            states: states(node, of: .pullRequest),
            closedWindow: duration(node, "closed-window", old: "closed-window-days", unit: "d"),
            drafts: bool(node, "drafts"),
            authors: authorFilter(node),
            reviewRequested: bool(node, "review-requested")
        )
    }

    private func issues(_ parent: Node) -> IssueOverrides {
        guard let node = table(parent, "issues") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "closed-window", "closed-window-days", "authors"])
        return IssueOverrides(
            show: bool(node, "show"),
            states: states(node, of: .issue),
            closedWindow: duration(node, "closed-window", old: "closed-window-days", unit: "d"),
            authors: authorFilter(node)
        )
    }

    private func workflowRuns(_ parent: Node) -> WorkflowRunOverrides {
        guard let node = table(parent, "workflow-runs") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "states", "finished-window", "finished-window-hours", "branches", "authors"])
        return WorkflowRunOverrides(
            show: bool(node, "show"),
            states: states(node, of: .workflowRun),
            finishedWindow: duration(node, "finished-window", old: "finished-window-hours", unit: "h"),
            branches: choice(node, "branches", WorkflowRunBranches.self),
            authors: authorFilter(node)
        )
    }

    /// The filters pull requests, issues or runs take that pings don't: each
    /// is rejected on its own line rather than ignored, so a wrong edit is caught.
    static let notPingKeys = ["states", "authors", "drafts", "review-requested"]

    private func pings(_ parent: Node) -> PingOverrides {
        guard let node = table(parent, "pings") else { return .init() }
        warnUnknownKeys(in: node, known: ["show", "seen-window"] + Self.notPingKeys)
        for key in Self.notPingKeys where node.table.contains(key: key) {
            error("`\(key)` doesn't apply to pings; `pings` takes only `show` and `seen-window`", at: node.path + [.key(key)])
        }
        return PingOverrides(show: bool(node, "show"), seenWindow: duration(node, "seen-window"))
    }

    /// The filters other kinds take that notes don't: each is rejected on
    /// its line, since a note lists while it's open in Notion.
    static let notNoteKeys = notPingKeys + ["seen-window"]

    private func notes(_ parent: Node) -> NoteOverrides {
        guard let node = table(parent, "notes") else { return .init() }
        warnUnknownKeys(in: node, known: ["show"] + Self.notNoteKeys)
        for key in Self.notNoteKeys where node.table.contains(key: key) {
            error("`\(key)` doesn't apply to notes; `notes` takes only `show`", at: node.path + [.key(key)])
        }
        return NoteOverrides(show: bool(node, "show"))
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

    /// `[menu] header-counts`: a list of kind names. A name that isn't a
    /// kind's is an error on its own line, with the nearest one suggested;
    /// so is a name listed twice.
    private func headerCounts(_ node: Node) -> [ItemKind]? {
        guard let texts = strings(node, "header-counts") else { return nil }
        let path = node.path + [.key("header-counts")]
        let valid = ItemKind.commandOrder.map(\.commandName)
        var kinds: [ItemKind] = []
        var spelled: [String: Int] = [:]
        var readable = true
        for text in texts {
            // Which appearance of this exact spelling it is, to find its line.
            let occurrence = spelled[text, default: 0]
            spelled[text] = occurrence + 1
            let line = map.line(for: path, value: text, occurrence: occurrence)
            guard let kind = ItemKind(commandName: text) else {
                let hint = Suggestion.nearest(to: text, in: valid).map { "did you mean `\($0)`?" }
                    ?? "expected " + valid.map { "`\($0)`" }.joined(separator: ", ")
                errors.append(ConfigurationIssue(line: line, message: "unknown kind `\(text)` in `header-counts` (\(hint))"))
                readable = false
                continue
            }
            if kinds.contains(kind) {
                errors.append(ConfigurationIssue(line: line, message: "`\(text)` is listed twice in `header-counts`"))
                readable = false
            }
            kinds.append(kind)
        }
        return readable ? kinds : nil
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
        warnings.append(ConfigurationIssue(
            line: map.line(for: path),
            message: "`hide-authors` is the old form: it's read as `authors = { hide = [\(written)] }` "
                + "in `[defaults.pull-requests]`, `[defaults.issues]` and `[defaults.workflow-runs]`; write that instead"
        ))
    }

    /// A `notifications` list: `[[defaults.notifications]]`, or a
    /// project's own when `inProject`. An app control event
    /// (`EventKind.isControl`) in a project's list, or with `authors`, is
    /// read but warned about: neither applies to it.
    private func notifications(_ parent: Node, inProject: Bool = false) -> [NotificationRule]? {
        guard let rules = tables(parent, "notifications") else { return nil }
        return rules.compactMap { node in
            warnUnknownKeys(in: node, known: ["event", "authors"])
            let authors = ruleAuthors(node)
            guard node.table.contains(key: "event") else {
                error("a notification rule needs an `event`", at: node.path)
                return nil
            }
            guard let event = choice(node, "event", EventKind.self, noun: "event") else { return nil }
            if event.isControl { warnControlRule(event, at: node, inProject: inProject, authors: authors ?? []) }
            return NotificationRule(event: event, authors: authors ?? [])
        }
    }

    /// The warning on a rule for an app control event: in a project's own
    /// list it's ignored, since only the top-level rules decide control
    /// events; otherwise its `authors` are, since no item's author sends one.
    private func warnControlRule(_ event: EventKind, at node: Node, inProject: Bool, authors: [AuthorSelector]) {
        let name = "`\(event.rawValue)`"
        if inProject {
            warnings.append(ConfigurationIssue(
                line: map.line(for: node.path + [.key("event")], value: event.rawValue),
                message: "\(name) is decided by `[[defaults.notifications]]` only; a project's rule for it is ignored"
            ))
        } else if !authors.isEmpty {
            warnings.append(ConfigurationIssue(
                line: map.line(for: node.path + [.key("authors")]),
                message: "`authors` doesn't apply to \(name), which no item's author sends; it's ignored"
            ))
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
        warnings.append(ConfigurationIssue(
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

    /// A duration (`closed-window = "30m"`), in seconds. The old key, a
    /// whole number of `unit`s (`closed-window-days = 7`), still reads,
    /// with a warning naming the new one; both in one table is an error on
    /// the old key's line.
    private func duration(_ node: Node, _ key: String, old: String, unit: Character) -> TimeInterval? {
        guard node.table.contains(key: old) else { return duration(node, key) }
        guard !setsBoth(node, key, old: old),
              let count = self.window(node, old),
              let seconds = ConfigurationDuration.units.first(where: { $0.unit == unit })?.seconds
        else { return nil }
        warnOldForm(node, old, readAs: key, value: count == 0 ? "0" : "\(count)\(unit)")
        return TimeInterval(count) * TimeInterval(seconds)
    }

    /// A duration (`snooze-duration = "1h"`), in seconds, whose old key
    /// was only named differently (`snooze`): it still reads, with a
    /// warning naming the new one; both in one table is an error on the
    /// old key's line.
    private func duration(_ node: Node, _ key: String, renamedFrom old: String) -> TimeInterval? {
        guard node.table.contains(key: old) else { return duration(node, key) }
        guard !setsBoth(node, key, old: old), let value = duration(node, old),
              let written = try? node.table.string(forKey: old)
        else { return nil }
        warnOldForm(node, old, readAs: key, value: written)
        return value
    }

    /// Whether the table sets `key` and its old form `old` both, which is
    /// an error on the old key's line.
    private func setsBoth(_ node: Node, _ key: String, old: String) -> Bool {
        guard node.table.contains(key: key) else { return false }
        error("`\(old)` is the old form of `\(key)`, which this table sets too; delete `\(old)`", at: node.path + [.key(old)])
        return true
    }

    /// The warning on an old key, giving the new key and value it's read as.
    private func warnOldForm(_ node: Node, _ old: String, readAs key: String, value: String) {
        warnings.append(ConfigurationIssue(
            line: map.line(for: node.path + [.key(old)]),
            message: "`\(old)` is the old form: it's read as `\(key) = \(Configuration.tomlString(value))`; write that instead"
        ))
    }

    /// A window written as a whole number and one unit, in seconds; one that
    /// doesn't read is rejected with what's allowed and the nearest spelling.
    private func duration(_ node: Node, _ key: String) -> TimeInterval? {
        guard node.table.contains(key: key) else { return nil }
        let path = node.path + [.key(key)]
        guard let text = try? node.table.string(forKey: key) else {
            error("`\(path.dotted)` must be a string: \(Self.windowForm)", at: path)
            return nil
        }
        do throws(ConfigurationDuration.Rejection) {
            return try ConfigurationDuration.parse(text)
        } catch {
            switch error {
            case .negative:
                self.error("`\(key)` can't be negative (got \(Configuration.tomlString(text)))", at: path)
            case .malformed(let suggestion):
                let hint = suggestion.map { "; did you mean \(Configuration.tomlString($0))?" } ?? ""
                self.error("`\(key)` must be \(Self.windowForm) (got \(Configuration.tomlString(text))\(hint))", at: path)
            }
        }
        return nil
    }

    /// What a window takes, as its rejections say it.
    static let windowForm = "a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\""

    /// A whole number, 0 or more: a count of rows, or an old window in days or hours.
    private func window(_ node: Node, _ key: String) -> Int? {
        guard let value = int(node, key) else { return nil }
        guard value >= 0 else {
            error("`\(key)` can't be negative (got \(value))", at: node.path + [.key(key)])
            return nil
        }
        return value
    }

    /// Why a project can't list `repository` again (in any letter case).
    static func duplicateRepositoryMessage(_ repository: String, project: String) -> String {
        "project `\(project)` lists repository `\(repository)` twice (names aren't case-sensitive)"
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

    /// Warns about each key that's neither `known` nor an `old` form the
    /// reader still takes; a misspelling is pointed at a `known` key only,
    /// never at an old one.
    private func warnUnknownKeys(in node: Node, known: [String], old: [String] = []) {
        for key in node.table.keys where !known.contains(key) && !old.contains(key) {
            let path = node.path + [.key(key)]
            let hint = Suggestion.nearest(to: key, in: known).map { "; did you mean `\($0)`?" } ?? ""
            warnings.append(ConfigurationIssue(line: map.line(for: path), message: "unknown setting `\(path.dotted)` (ignored\(hint))"))
        }
    }

    private func typeError(_ node: Node, _ key: String, expected: String, _ underlying: any Error) {
        let path = node.path + [.key(key)]
        let (tomlLine, _) = ConfigurationIssue.splitLine(from: String(describing: underlying))
        errors.append(ConfigurationIssue(line: tomlLine ?? map.line(for: path), message: "`\(path.dotted)` must be \(expected)"))
    }

    private func error(_ message: String, at path: ConfigPath, value: String? = nil) {
        errors.append(ConfigurationIssue(line: map.line(for: path, value: value), message: message))
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
        case .ping: "ping"
        case .note: "note"
        }
    }
}
