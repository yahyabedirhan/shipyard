import Foundation
@testable import ShipyardCommand
@testable import ShipyardConfig
@testable import ShipyardControl
@testable import ShipyardCore
@testable import ShipyardNotices
@testable import ShipyardPings
import Testing

// The shipyard agent skill (`skills/shipyard/SKILL.md`) teaches agents the
// configuration file. These tests read it from the source tree, so it can't
// drift from what the code reads and validates.

private let skillURL = repositoryRoot.appendingPathComponent("skills/shipyard/SKILL.md")
private let presetsURL = repositoryRoot.appendingPathComponent("skills/shipyard/presets.md")
private let noticesURL = repositoryRoot.appendingPathComponent("skills/shipyard/references/notices.md")

private func skill() throws -> String {
    try String(contentsOf: skillURL, encoding: .utf8)
}

/// The body of every ```toml fence in `text`, in order.
private func tomlBlocks(in text: String) -> [String] {
    var blocks: [String] = []
    var current: [String]?
    var indent = 0
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if current == nil, trimmed == "```toml" {
            current = []
            indent = line.prefix(while: { $0 == " " }).count
        } else if current != nil, trimmed == "```" {
            blocks.append(current!.joined(separator: "\n") + "\n")
            current = nil
        } else if current != nil {
            current!.append(String(line.dropFirst(min(indent, line.prefix(while: { $0 == " " }).count))))
        }
    }
    return blocks
}

/// The key-like words in a code span: `[menu-bar] count` has `menu-bar` and `count`.
private func words(_ span: String) -> Set<String> {
    Set(span.split { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.map(String.init))
}

/// `prose` split at blank lines into paragraphs, list runs and tables; a
/// table stays with the paragraph that introduces it.
private func proseBlocks(_ prose: String) -> [String] {
    var blocks: [[String]] = []
    var current: [String] = []
    for line in prose.components(separatedBy: "\n") {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            if !current.isEmpty { blocks.append(current) }
            current = []
        } else if current.isEmpty, line.hasPrefix("|"), let introduction = blocks.popLast() {
            current = introduction + [line]
        } else {
            current.append(line)
        }
    }
    if !current.isEmpty { blocks.append(current) }
    return blocks.map { $0.joined(separator: "\n") }
}

@Suite("Agent skill document")
struct SkillDocumentTests {
    @Test("it has the frontmatter `npx skills add` needs, named after its folder")
    func frontmatter() throws {
        let frontmatter = try SkillFrontmatter(document: skill())
        #expect(frontmatter["name"] == "shipyard")
        #expect(skillURL.deletingLastPathComponent().lastPathComponent == "shipyard")
        let description = try #require(frontmatter["description"])
        #expect(description.count > 20)
        // "Change my shipyard" means its configuration. The skill is for any
        // shipyard user: shipyard's own repository and code are AGENTS.md's.
        #expect(description.contains("my shipyard"))
        #expect(description.contains("the shipyard app"))
        let described = words(description.lowercased())
        #expect(described.isDisjoint(with: ["repository", "repo", "code", "source"]), "the description speaks to shipyard's maintainers")
    }

    @Test("its frontmatter is read as strict YAML, so an unquoted colon in a value is refused")
    func frontmatterIsStrictYAML() throws {
        let unquoted = "---\nname: shipyard\ndescription: Edit it (its layout): watch repositories.\n---\n"
        #expect(throws: SkillFrontmatter.Invalid.self) { try SkillFrontmatter(document: unquoted) }

        let quoted = "---\nname: shipyard\ndescription: \"Edit it (its layout): watch \\\"repositories\\\".\"\n---\n"
        #expect(try SkillFrontmatter(document: quoted)["description"] == "Edit it (its layout): watch \"repositories\".")

        let singleQuoted = "---\nname: shipyard\ndescription: 'Edit shipyard''s file: all of it.'\n---\n"
        #expect(try SkillFrontmatter(document: singleQuoted)["description"] == "Edit shipyard's file: all of it.")

        for broken in [
            "description: ends with a colon:",
            "description: a # comment eats the rest",
            "description: \"never closed",
            "description: 'never closed",
            "description: \"closed\" then more",
            "description: >-",
        ] {
            #expect(throws: SkillFrontmatter.Invalid.self, "\(broken)") {
                try SkillFrontmatter(document: "---\nname: shipyard\n\(broken)\n---\n")
            }
        }
    }

    @Test("every TOML example decodes cleanly and validates against the schema")
    func examplesDecode() throws {
        let blocks = tomlBlocks(in: try skill())
        #expect(blocks.count >= 5)
        let schema = try loadSchema()
        for block in blocks {
            do throws(ConfigError) {
                let result = try Configuration.decode(block)
                #expect(result.warnings.isEmpty, "warnings in:\n\(block)")
            } catch {
                Issue.record("rejected: \(error)\nin:\n\(block)")
            }
            #expect(try violations(block, schema: schema) == [], "schema violations in:\n\(block)")
        }
    }

    @Test("the worked requests configure what they say")
    func workedRequests() throws {
        let blocks = tomlBlocks(in: try skill()).map { try? Configuration.decode($0).configuration }
        // "notify me when others open PRs here"
        let others = blocks.compactMap { $0?.projects.first?.notifications }
        #expect(others.contains([NotificationRule(event: .prOpened, authors: [.others])]))
        // "show issues for this project": issues on, the window left at its default
        let issues = try #require(blocks.compactMap { $0?.projects.first }.first { $0.issues == IssueOverrides(show: true) })
        let config = Configuration()
        #expect(config.settings(for: issues).issues == IssueSettings(show: true, closedWindow: config.defaults.issues.closedWindow))
        // "group these repos"
        #expect(blocks.contains { ($0?.projects.first?.repositories.count ?? 0) > 1 })
        // "hide dependabot": its pull requests, in every project
        #expect(blocks.contains { $0?.defaults.pullRequests.authors == AuthorFilter(hide: [.login("dependabot[bot]")]) })
        // "only show what other people open in this project": me and bots hidden, per kind
        let incoming = blocks.compactMap { $0?.projects.first }.first { $0.pullRequests.authors.hide == [.me, .bots] }
        #expect(incoming?.issues.authors.hide == [.me, .bots])
        // "only show open PRs and issues here"
        let states = blocks.compactMap { $0?.projects.first }.first { $0.pullRequests.states == [.open] }
        #expect(states?.issues == IssueOverrides(show: true, states: [.open]))
        // "switch the menu to tabs"
        #expect(blocks.contains { $0?.menu.layout == .tabs })
        // "show CI runs for this project and tell me when they fail": runs on for that
        // project alone, with the default project rules kept beside run.failed
        let runs = try #require(blocks.compactMap { $0?.projects.first }.first { $0.workflowRuns.show == true })
        #expect(config.settings(for: runs).workflowRuns.finishedWindow == config.defaults.workflowRuns.finishedWindow)
        #expect(runs.notifications == [.prOpened, .pingSent, .agentNotice, .runFailed].map { NotificationRule(event: $0) })
        // "shipyard doesn't notify me about pings": a file with its own rules adds `ping.sent`
        #expect(blocks.contains { config in
            let rules = config?.defaults.notifications ?? []
            return rules.contains(NotificationRule(event: .pingSent)) && rules.count > 1
        })
    }

    @Test("it teaches the ping command as it's built: every flag, the exit codes, and examples that read")
    func pingCommand() throws {
        let text = try skill()
        #expect(!text.contains("there is no CLI"))
        // Every flag the command's own help lists is named in a code span.
        let flags = Set(PingCommand.usageText.matches(of: /--[a-z]+/).map { String($0.output) })
        #expect(flags.isSuperset(of: ["--body", "--from", "--id", "--open", "--app", "--herdr", "--repo", "--project"]))
        for flag in flags.sorted() where flag != "--help" {
            #expect(text.contains("`\(flag)"), "`\(flag)` isn't named")
        }
        #expect(text.contains("`--`"))
        #expect(text.contains("shipyard ping withdraw <id>"))
        #expect(text.contains("`\(PingCommand.herdrPaneVariable)`"))
        #expect(text.contains("~/.local/bin/shipyard"))
        #expect(text.contains("**\(PanelText.linkCLI)**"))
        #expect(text.contains("exit 1") && text.contains("exit 2") && text.contains("exits 0"))
        #expect(CommandResult.failedStatus == 1 && CommandResult.usageStatus == 2)

        // Every example command reads as the command reads it.
        let examples = shellExamples(in: text, command: "ping")
        #expect(examples.count >= 4)
        var withdrawn = 0
        for words in examples {
            let arguments = Array(words.dropFirst(2))
            if arguments.first == "withdraw" {
                withdrawn += 1
                #expect(arguments.count == 2 && PingCommand.isID(arguments[1]), "\(words)")
                continue
            }
            if case .failure(let error) = PingCommand.Request.parse(arguments, herdrPane: "w1:p3") {
                Issue.record("\(words) doesn't read: \(error.message)")
            }
        }
        #expect(withdrawn > 0)
        let actions = examples.compactMap { try? PingCommand.Request.parse(Array($0.dropFirst(2)), herdrPane: "w1:p3").get() }
        #expect(actions.contains { $0.action == .herdr("w1:p3") && $0.id != nil })
        #expect(actions.contains { if case .url = $0.action { true } else { false } })
    }

    @Test("it teaches app control as it's built: every subcommand, the exit codes, and examples that read")
    func appControl() throws {
        let text = try skill()
        let flowing = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // The synopsis is the commands' own, word for word.
        for usage in [ControlCommand.usageText, PanelCommand.usageText, ScreenshotCommand.usageText, LeaseCommand.usageText] {
            let synopsis = usage.components(separatedBy: "\n\n")[0]
                .replacingOccurrences(of: "usage: ", with: "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(flowing.contains(synopsis), "`\(synopsis)` isn't taught")
        }
        // The refusals and the fallback's note, in the command's words.
        for line in [
            ControlCommand.notRunning, "captured by rendering: <why>", "runs on the Mac, where the app is",
            "use a folder with a shorter path", "the menu uses the list layout; tabs need `[menu] layout = \"tabs\"`",
        ] {
            #expect(text.contains(line), "`\(line)` isn't quoted")
        }
        // The lease's refusals, in the lease's own words, its times and counts as placeholders.
        let now = Date(timeIntervalSince1970: 0)
        let term = ControlLease.Term(
            holder: Holder(key: "k", name: "<name>", place: "<place>"), taken: now, ends: now.addingTimeInterval(48)
        )
        for refusal in [ControlLease.Refusal.inUse(term), .waitedOut(seconds: 30, term), .stopped] {
            let line = refusal.message(at: now, timeZone: TimeZone(identifier: "UTC")!)
                .replacing(/\d\d:\d\d:\d\d/, with: "<HH:mm:ss>")
                .replacing(/\d+s/, with: "<n>s")
            #expect(text.contains(line), "`\(line)` isn't quoted")
        }
        #expect(text.contains("`you hold shipyard until <HH:mm:ss>`") && text.contains("`released shipyard`"))
        #expect(text.contains("<folder>/shipyard/config.toml"))
        #expect(text.contains("**0**") && text.contains("**1**") && text.contains("**2**"))

        // Every example reads as its command reads it, and each subcommand and option has one.
        let demo = FileManager.default.temporaryDirectory.appendingPathComponent("skill-demo-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: demo) }
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])
        var taught: Set<String> = []
        for command in ["app", "panel", "screenshot", "control"] {
            for words in shellExamples(in: text, command: command) {
                var arguments = Array(words.dropFirst(2))
                // A demo folder must exist to read; the example's own is made by its block.
                if let flag = arguments.firstIndex(of: "--demo"), flag + 1 < arguments.count { arguments[flag + 1] = demo.path }
                let reads = switch command {
                case "app": (try? ControlCommand.parse(arguments, environment: environment).get()) != nil
                case "panel": (try? PanelCommand.parse(arguments).get()) != nil
                case "control": (try? LeaseCommand.parse(arguments).get()) != nil
                default: (try? ScreenshotCommand.parse(arguments, workingDirectory: environment.workingDirectory).get()) != nil
                }
                #expect(reads, "\(words) doesn't read")
                taught.insert(command == "screenshot" ? command : "\(command) \(arguments.first ?? "")")
                for option in ["--demo", "--json", "--appearance", "--menu-bar-icon", "--with-indicator", "--wait"] where arguments.contains(option) {
                    taught.insert("\(command) \(option)")
                }
            }
        }
        let every: Set<String> = [
            "app open", "app --demo", "app quit", "app status", "app --json",
            "panel open", "panel close", "panel fold", "panel unfold", "panel show-more", "panel tab",
            "screenshot", "screenshot --appearance", "screenshot --menu-bar-icon", "screenshot --with-indicator",
            "control take", "control --wait", "control release",
        ]
        #expect(every.subtracting(taught).isEmpty, "no example for \(every.subtracting(taught).sorted())")
    }

    @Test("every key the schema declares is named")
    func namesEveryKey() throws {
        let text = try skill()
        let schema = try loadSchema()
        let leaves = Set(declaredPaths(schema, root: schema).map { path in
            String(path.split(separator: ".").last!).replacingOccurrences(of: "[]", with: "")
        })
        // The words inside `code spans`: `[menu-bar] count` names `menu-bar` and `count`.
        // Fenced examples don't count: a key has to be named in the prose.
        var inFence = false
        let prose = text.components(separatedBy: "\n").filter { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); return false }
            return !inFence
        }.joined(separator: "\n")
        let spans = prose.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let named = Set(spans.flatMap { span in
            span.split { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.map(String.init)
        })
        for key in leaves.sorted() {
            #expect(named.contains(key), "`\(key)` isn't named")
        }
        // A nested key is named beside its table, as `[menu-bar] count` or
        // `pull-requests.show`, so `show` in one table doesn't cover another's.
        let spanWords = spans.map(words)
        for path in declaredPaths(schema, root: schema).sorted() {
            let segments = path.split(separator: ".").map(String.init)
            guard segments.count > 1, !segments[segments.count - 2].hasSuffix("[]") else { continue }
            let (table, key) = (segments[segments.count - 2], segments[segments.count - 1])
            #expect(spanWords.contains { $0.contains(table) && $0.contains(key) }, "`\(path)` isn't named beside `\(table)`")
        }
        // A key of an array's elements (a project's `name`, a rule's `event`)
        // is named in a code span in the same paragraph or table as a span
        // naming its array (`[[projects]]`, `notifications`), so a bare
        // mention elsewhere doesn't count.
        let blockWords = proseBlocks(prose).map { block in
            block.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map { words($0.element) }
        }
        for path in declaredPaths(schema, root: schema).sorted() {
            let segments = path.split(separator: ".").map(String.init)
            guard segments.count > 1, segments[segments.count - 2].hasSuffix("[]") else { continue }
            let array = String(segments[segments.count - 2].dropLast(2))
            let key = segments[segments.count - 1]
            let named = blockWords.contains { spans in
                spans.contains { $0.contains(array) } && spans.contains { $0.contains(key) }
            }
            #expect(named, "`\(path)` isn't named next to `\(array)`")
        }
    }

    @Test("every key's default is the one the code uses")
    func defaults() throws {
        let text = try skill()
        let c = Configuration()
        func literal<T: RawRepresentable>(_ choice: T) -> String where T.RawValue == String { "\"\(choice.rawValue)\"" }
        func window(_ seconds: TimeInterval) -> String { "\"\(WindowDuration.text(seconds))\"" }
        // A kind's states, in the order the file writes them, when the default is all of them.
        func states(_ kind: ItemKind, _ value: Set<StateGroup>) -> String {
            value == Set(StateGroup.all(for: kind)) ? "[" + StateGroup.all(for: kind).map(literal).joined(separator: ", ") + "]" : "?"
        }
        let rows: [(String, String)] = [
            ("version", "\(c.version)"),
            ("refresh-interval-seconds", "\(c.refreshIntervalSeconds)"),
            ("launch-at-login", "\(c.launchAtLogin)"),
            ("[menu-bar] count", literal(c.menuBar.count)),
            ("[menu] layout", literal(c.menu.layout)),
            ("[rate-limit] show", literal(c.rateLimit.show)),
            ("[rate-limit] max-share-percent", "\(c.rateLimit.maxSharePercent)"),
            ("[attention] unseen", "\(c.attention.unseen)"),
            ("[attention] changed", "\(c.attention.changed)"),
            ("[attention] review-requested", "\(c.attention.reviewRequested)"),
            ("[attention] checks-failed", "\(c.attention.checksFailed)"),
            ("pull-requests.show", "\(c.defaults.pullRequests.show)"),
            ("pull-requests.states", states(.pullRequest, c.defaults.pullRequests.states)),
            ("issues.states", states(.issue, c.defaults.issues.states)),
            ("workflow-runs.states", states(.workflowRun, c.defaults.workflowRuns.states)),
            ("pull-requests.closed-window", window(c.defaults.pullRequests.closedWindow)),
            ("pull-requests.drafts", "\(c.defaults.pullRequests.drafts)"),
            ("pull-requests.authors", c.defaults.pullRequests.authors == AuthorFilter() ? "{ show = [], hide = [] }" : "?"),
            ("issues.authors", c.defaults.issues.authors == AuthorFilter() ? "{ show = [], hide = [] }" : "?"),
            ("workflow-runs.authors", c.defaults.workflowRuns.authors == AuthorFilter() ? "{ show = [], hide = [] }" : "?"),
            ("issues.show", "\(c.defaults.issues.show)"),
            ("issues.closed-window", window(c.defaults.issues.closedWindow)),
            ("workflow-runs.show", "\(c.defaults.workflowRuns.show)"),
            ("workflow-runs.finished-window", window(c.defaults.workflowRuns.finishedWindow)),
            ("workflow-runs.branches", literal(c.defaults.workflowRuns.branches)),
            ("[defaults] group-by", literal(c.defaults.arrangement.groupBy)),
            ("[defaults] sort-by", literal(c.defaults.arrangement.sortBy)),
            ("[defaults] show-first", "\(c.defaults.arrangement.showFirst)"),
            ("[defaults] archived", "\(c.defaults.archived)"),
            ("[defaults] forks", "\(c.defaults.forks)"),
            ("pings.show", "\(c.defaults.pings.show)"),
            // Written in hours, as the configuration header writes it, rather than "1d".
            ("pings.seen-window", c.defaults.pings.seenWindow == 24 * 3600 ? "\"24h\"" : "?"),
        ]
        for (key, value) in rows {
            #expect(text.contains("| `\(key)` | `\(value)` |"), "no row `\(key)` = `\(value)`")
        }
        #expect(c.defaults.arrangement.subsections == nil)
        #expect(text.contains("| `[defaults] subsections` | unset |"))
        #expect(c.herdr.terminal == nil)
        #expect(text.contains("| `[herdr] terminal` | unset |"))
        #expect(c.defaults.notifications == [.prOpened, .pingSent, .agentNotice, .controlStarted, .controlEnded].map { NotificationRule(event: $0) })
        #expect(text.contains(
            "| `notifications` | five rules: `pr.opened`, `ping.sent`, `agent.notice`, `control.started` and `control.ended`, each `authors = []` |"
        ))
    }

    @Test("every choice, event and author filter is listed")
    func choices() throws {
        let text = try skill()
        let values = EventKind.allCases.map(\.rawValue) + AuthorSelector.groups.map(\.description) + NotificationRule.legacyAuthors
            + MenuBarCount.allCases.map(\.rawValue) + MenuLayout.allCases.map(\.rawValue) + RateLimitDisplay.allCases.map(\.rawValue)
            + WorkflowRunBranches.allCases.map(\.rawValue) + GroupBy.allCases.map(\.rawValue) + SortBy.allCases.map(\.rawValue)
            + StateGroup.allCases.map(\.rawValue) + RepositoryGroup.allCases.map(\.rawValue)
        for value in values {
            #expect(text.contains("`\(value)`") || text.contains("`\"\(value)\"`"), "`\(value)` isn't listed")
        }
        for event in EventKind.allCases {
            #expect(text.contains("| `\(event.rawValue)` |"), "event `\(event.rawValue)` has no row")
        }
    }

    @Test("its presets page shows the app's presets, file for file, and the skill says when to start from one")
    func presets() throws {
        let page = try String(contentsOf: presetsURL, encoding: .utf8)
        // The examples the page puts where onboarding's picks go.
        let examples: [String: [NewProject]] = [
            Preset.myAgents.name: [
                NewProject(name: "hello-world", repositories: ["octocat/hello-world"]),
                NewProject(name: "Spoon-Knife", repositories: ["octocat/Spoon-Knife"]),
            ],
        ]
        // One `## `name`` section per preset, in the app's order, each with its file.
        let sections = page.components(separatedBy: "\n## ").dropFirst()
        let named = sections.filter { $0.hasPrefix("`") }
        #expect(named.map { String($0.prefix { $0 != "\n" }) } == Preset.all.map { "`\($0.name)`" })
        for (preset, section) in zip(Preset.all, named) {
            let blocks = tomlBlocks(in: section)
            #expect(blocks == [preset.text(projects: examples[preset.name] ?? [])], "`\(preset.name)` differs from the app's")
        }
        let text = try skill()
        #expect(text.contains("[presets.md](presets.md)"))
        for preset in Preset.all {
            #expect(text.contains("`\(preset.name)`"), "the skill doesn't name `\(preset.name)`")
        }
    }

    @Test("its notices reference teaches the notify command as it's built: the synopsis, every flag, the refusals, and examples that read")
    func notifyCommand() throws {
        let page = try String(contentsOf: noticesURL, encoding: .utf8)
        #expect(try skill().contains("[references/notices.md](references/notices.md)"))
        let flowing = page.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let synopsis = NotifyCommand.usageText.components(separatedBy: "\n\n")[0]
            .replacingOccurrences(of: "usage: ", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(flowing.contains(synopsis), "`\(synopsis)` isn't taught")
        for flag in Set(NotifyCommand.usageText.matches(of: /--[a-z]+/).map { String($0.output) }) {
            #expect(page.contains("`\(flag)"), "`\(flag)` isn't named")
        }
        #expect(page.contains(ControlNoticeRoute.notRunning))
        #expect(page.contains("notices are off for project `<name>`"))
        #expect(page.contains("**0**") && page.contains("**1**") && page.contains("**2**"))
        let examples = shellExamples(in: page, command: "notify")
        #expect(examples.count >= 3)
        for words in examples {
            if case .failure(let error) = NotifyCommand.parse(Array(words.dropFirst(2))) {
                Issue.record("\(words) doesn't read: \(error.message)")
            }
        }
    }

    @Test("it names the path, the schema and the installer's repository")
    func pointers() throws {
        let text = try skill()
        #expect(text.contains("$XDG_CONFIG_HOME/shipyard/config.toml"))
        #expect(text.contains("~/.config/shipyard/config.toml"))
        #expect(text.contains("#:schema \(Configuration.schemaURL)"))
        #expect(text.contains("taplo check"))
        // The app's own check: its error banner, in the words the panel shows.
        #expect(text.contains("Using the last valid configuration."))
        // The app's verdict, where an agent reads it, with the fields it names.
        #expect(text.contains("~/Library/Application Support/Shipyard/\(ConfigStatusStore.fileName)"))
        for field in ["accepted", "configModified", "problems", "line", "banner", "warnings"] {
            #expect(text.contains("`\(field)`") || text.contains("\"\(field)\""), "`\(field)` isn't named")
        }
        #expect(text.contains("echo \"taplo exit status: $?\""))
        #expect(SkillInstaller.command.contains("skills add yahyabedirhan/shipyard"))
    }
}

/// The `shipyard <command>` lines of the ```sh fences in `text`, each split
/// into words: a line ending in `\` continues on the next, `||` and `&&`
/// separate commands, and a synopsis (with `<placeholders>`) is skipped.
private func shellExamples(in text: String, command: String) -> [[String]] {
    var examples: [[String]] = []
    var inShell = false
    var pending = ""
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "```sh" { inShell = true; continue }
        if trimmed == "```" { inShell = false; continue }
        guard inShell else { continue }
        if trimmed.hasSuffix("\\") { pending += String(trimmed.dropLast()) + " "; continue }
        let joined = pending + trimmed
        pending = ""
        for part in joined.components(separatedBy: "||").flatMap({ $0.components(separatedBy: "&&") }) {
            let words = shellWords(part.trimmingCharacters(in: .whitespaces))
            guard words.count > 1, words[0] == "shipyard", words[1] == command, !part.contains("<") else { continue }
            examples.append(words)
        }
    }
    return examples
}

/// `command` split into words as a shell splits it, for double-quoted words and plain ones.
private func shellWords(_ command: String) -> [String] {
    var words: [String] = []
    var current = ""
    var quoted = false
    var started = false
    for character in command {
        if character == "\"" {
            quoted.toggle()
            started = true
        } else if character == " ", !quoted {
            if started { words.append(current) }
            current = ""
            started = false
        } else {
            current.append(character)
            started = true
        }
    }
    if started { words.append(current) }
    return words
}
