import Foundation
@testable import ShipyardCore
import Testing

// The shipyard agent skill (`skills/shipyard/SKILL.md`) teaches agents the
// configuration file. These tests read it from the source tree, so it can't
// drift from what the code reads and validates.

private let skillURL = repositoryRoot.appendingPathComponent("skills/shipyard/SKILL.md")

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

@Suite("Agent skill document")
struct SkillDocumentTests {
    @Test("it has the frontmatter `npx skills add` needs, named after its folder")
    func frontmatter() throws {
        let lines = try skill().components(separatedBy: "\n")
        #expect(lines.first == "---")
        let end = try #require(lines.dropFirst().firstIndex(of: "---"))
        let fields = lines[1..<end]
        #expect(fields.contains("name: shipyard"))
        #expect(skillURL.deletingLastPathComponent().lastPathComponent == "shipyard")
        let description = try #require(fields.first { $0.hasPrefix("description: ") })
        #expect(description.count > "description: ".count + 20)
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
        #expect(others.contains([NotificationRule(event: .prOpened, authors: .others)]))
        // "show issues for this project": issues on, the window left at its default
        let issues = try #require(blocks.compactMap { $0?.projects.first }.first { $0.issues.show == true })
        let config = Configuration()
        #expect(config.settings(for: issues).issues == IssueSettings(show: true, closedWindowDays: config.defaults.issues.closedWindowDays))
        // "group these repos"
        #expect(blocks.contains { ($0?.projects.first?.repositories.count ?? 0) > 1 })
        // "hide dependabot"
        #expect(blocks.contains { $0?.hideAuthors == ["dependabot[bot]"] })
        // "switch the menu to tabs"
        #expect(blocks.contains { $0?.menu.layout == .tabs })
        // "show CI runs for this project and tell me when they fail": runs on for that
        // project alone, with the default pr.opened rule kept beside run.failed
        let runs = try #require(blocks.compactMap { $0?.projects.first }.first { $0.workflowRuns.show == true })
        #expect(config.settings(for: runs).workflowRuns.finishedWindowHours == config.defaults.workflowRuns.finishedWindowHours)
        #expect(runs.notifications == [NotificationRule(event: .prOpened, authors: .any), NotificationRule(event: .runFailed, authors: .any)])
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
        // Keys of an array's elements (a project's `name`, a rule's `event`)
        // are named in that element's own table.
        let spanWords = spans.map { span in
            Set(span.split { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.map(String.init))
        }
        for path in declaredPaths(schema, root: schema).sorted() {
            let segments = path.split(separator: ".").map(String.init)
            guard segments.count > 1, !segments[segments.count - 2].hasSuffix("[]") else { continue }
            let (table, key) = (segments[segments.count - 2], segments[segments.count - 1])
            #expect(spanWords.contains { $0.contains(table) && $0.contains(key) }, "`\(path)` isn't named beside `\(table)`")
        }
    }

    @Test("every key's default is the one the code uses")
    func defaults() throws {
        let text = try skill()
        let c = Configuration()
        func literal<T: RawRepresentable>(_ choice: T) -> String where T.RawValue == String { "\"\(choice.rawValue)\"" }
        let rows: [(String, String)] = [
            ("version", "\(c.version)"),
            ("refresh-interval-seconds", "\(c.refreshIntervalSeconds)"),
            ("launch-at-login", "\(c.launchAtLogin)"),
            ("hide-authors", c.hideAuthors.isEmpty ? "[]" : "?"),
            ("[menu-bar] count", literal(c.menuBar.count)),
            ("[menu] layout", literal(c.menu.layout)),
            ("[rate-limit] show", literal(c.rateLimit.show)),
            ("[rate-limit] max-share-percent", "\(c.rateLimit.maxSharePercent)"),
            ("[attention] unseen", "\(c.attention.unseen)"),
            ("[attention] changed", "\(c.attention.changed)"),
            ("[attention] review-requested", "\(c.attention.reviewRequested)"),
            ("[attention] checks-failed", "\(c.attention.checksFailed)"),
            ("pull-requests.show", "\(c.defaults.pullRequests.show)"),
            ("pull-requests.closed-window-days", "\(c.defaults.pullRequests.closedWindowDays)"),
            ("pull-requests.drafts", "\(c.defaults.pullRequests.drafts)"),
            ("issues.show", "\(c.defaults.issues.show)"),
            ("issues.closed-window-days", "\(c.defaults.issues.closedWindowDays)"),
            ("workflow-runs.show", "\(c.defaults.workflowRuns.show)"),
            ("workflow-runs.finished-window-hours", "\(c.defaults.workflowRuns.finishedWindowHours)"),
            ("workflow-runs.branches", literal(c.defaults.workflowRuns.branches)),
        ]
        for (key, value) in rows {
            #expect(text.contains("| `\(key)` | `\(value)` |"), "no row `\(key)` = `\(value)`")
        }
        #expect(c.defaults.notifications == [NotificationRule(event: .prOpened, authors: .any)])
        #expect(text.contains("| `notifications` | one rule: `pr.opened`, `any` |"))
    }

    @Test("every choice, event and author filter is listed")
    func choices() throws {
        let text = try skill()
        let values = EventKind.allCases.map(\.rawValue) + AuthorFilter.allCases.map(\.rawValue)
            + MenuBarCount.allCases.map(\.rawValue) + MenuLayout.allCases.map(\.rawValue) + RateLimitDisplay.allCases.map(\.rawValue)
            + WorkflowRunBranches.allCases.map(\.rawValue)
        for value in values {
            #expect(text.contains("`\(value)`") || text.contains("`\"\(value)\"`"), "`\(value)` isn't listed")
        }
        for event in EventKind.allCases {
            #expect(text.contains("| `\(event.rawValue)` |"), "event `\(event.rawValue)` has no row")
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
        #expect(SkillInstaller.command.contains("skills add yahyabedirhan/shipyard"))
    }
}
