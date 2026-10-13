import Foundation

/// How much the panel holds: the number of projects, the items each lists,
/// and how many of them need attention. The lab's stand-in for a refresh.
public struct FixtureVolume: Equatable, Hashable, Sendable {
    public var name: String
    public var projects: Int
    public var itemsPerProject: Int
    /// The share of open items that need attention.
    public var attentionShare: Double
    /// The share of a project's rows that also appear in another project
    /// (a repository in two projects): the All tab lists them once.
    public var sharedShare: Double

    public init(name: String, projects: Int, itemsPerProject: Int, attentionShare: Double = 0.25, sharedShare: Double = 0.05) {
        self.name = name
        self.projects = projects
        self.itemsPerProject = itemsPerProject
        self.attentionShare = attentionShare
        self.sharedShare = sharedShare
    }

    /// How many rows the All tab lists, about: every project's rows, less
    /// the shared ones.
    public var allTabRows: Int {
        Int(Double(projects * itemsPerProject) * (1 - sharedShare))
    }

    /// A few projects with a handful of items: the panel as most people see it.
    public static let light = FixtureVolume(name: "Light", projects: 3, itemsPerProject: 12)
    /// About the maintainer's panel today: 11 projects, the app's state
    /// knowing some 1,200 items, a few hundred listed at once.
    public static let maintainer = FixtureVolume(name: "Maintainer", projects: 11, itemsPerProject: 40)
    /// Twice the projects, more items each.
    public static let heavy = FixtureVolume(name: "Heavy", projects: 20, itemsPerProject: 80)
    /// Past what anyone has yet: where the All tab breaks down.
    public static let extreme = FixtureVolume(name: "Extreme", projects: 30, itemsPerProject: 120)

    public static let all: [FixtureVolume] = [.light, .maintainer, .heavy, .extreme]
}

/// Sample data for the lab: projects with pull requests, issues, workflow
/// runs, pings and notes, deterministic for a seed so a screenshot or a
/// measurement can be repeated. Nothing here talks to GitHub, Notion or
/// the ping store.
public enum Fixtures {
    /// A fixed "now", so ages read the same in every screenshot.
    public static let now = Date(timeIntervalSince1970: 1_791_900_000)

    public static let projectNames = [
        "harbor", "atlas", "lighthouse", "beacon", "compass", "anchor", "tide", "keel",
        "mast", "rudder", "sextant", "galley", "bosun", "dinghy", "regatta", "jetty",
        "lagoon", "estuary", "breakwater", "capstan", "halyard", "spinnaker", "mooring",
        "drydock", "quay", "wharf", "pier", "slipway", "buoy", "cove",
    ]

    /// The menu model for `volume`: one section per project in the tabs or
    /// list layout, its rows arranged as the app arranges them, attention
    /// set on a share of open rows.
    /// `runningRuns` false finishes every running workflow run (succeeded),
    /// taking its row's repeating pulse out of the panel.
    public static func model(_ volume: FixtureVolume, layout: MenuLayout = .tabs, runningRuns: Bool = true, seed: UInt64 = 7) -> MenuModel {
        var random = SeededRandom(seed: seed)
        let names = (0..<volume.projects).map { index in
            index < projectNames.count ? projectNames[index] : "\(projectNames[index % projectNames.count])-\(index / projectNames.count + 1)"
        }
        var perProject: [[MenuRow]] = names.enumerated().map { index, name in
            rows(project: name, count: volume.itemsPerProject, attentionShare: volume.attentionShare, random: &random, salt: index)
                .map { row in
                    guard !runningRuns, row.state == .running else { return row }
                    var item = row.item
                    item.state = .succeeded
                    item.checks = .passed
                    item.closedAt = item.updatedAt
                    return MenuRow(item, needsAttention: false)
                }
        }
        // A repository in two projects: its rows appear in both.
        if names.count > 1 {
            for index in perProject.indices {
                let shared = Int(Double(perProject[index].count) * volume.sharedShare)
                let into = (index + 1) % perProject.count
                perProject[into].append(contentsOf: perProject[index].prefix(shared))
            }
        }
        let sections = names.enumerated().map { index, name in
            let rows = perProject[index]
            let groups = Arrangement.groups(
                rows: rows,
                project: name,
                settings: ArrangementSettings(),
                layout: layout,
                now: now
            )
            var section = MenuSection(
                name: name,
                title: title(name),
                groups: groups,
                showsRepository: true,
                attentionCount: rows.filter(\.needsAttention).count,
                repositories: ["shipyard-lab/\(name)", "shipyard-lab/\(name)-web"]
            )
            section.headerCounts = HeaderCount.counts(rows, kinds: MenuModel.headerCountOrder)
            section.newNote = index % 3 == 0 ? .ready : nil
            return section
        }
        var counts = AttentionCounts()
        var counted = Set<String>()
        for row in sections.flatMap(\.rows) where row.needsAttention && counted.insert(row.id).inserted {
            counts.add(row.kind)
        }
        return MenuModel(
            sections: sections,
            attention: counts,
            menuBarLabel: .total(counts.total),
            layout: layout,
            lastUpdated: now
        )
    }

    public static func title(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Rows

    static func rows(project: String, count: Int, attentionShare: Double, random: inout SeededRandom, salt: Int) -> [MenuRow] {
        (0..<count).map { index in
            let item = makeItem(project: project, index: index, random: &random)
            var row = MenuRow(item)
            if item.kind != .note, item.state.isOpen || item.state == .failed, random.chance(attentionShare) {
                row.needsAttention = true
                row.attentionReasons = item.kind == .ping ? [.unseen] : [random.pick([.unseen, .changed, .reviewRequested, .checksFailed])]
            }
            return row
        }
    }

    static func makeItem(project: String, index: Int, random: inout SeededRandom) -> Item {
        let repository = random.chance(0.7) ? "shipyard-lab/\(project)" : "shipyard-lab/\(project)-web"
        let number = 100 + index * 3 + random.int(3)
        let created = now.addingTimeInterval(-Double(random.int(14 * 86_400) + 60))
        let updated = min(now, created.addingTimeInterval(Double(random.int(3 * 86_400))))
        let roll = random.double()
        switch roll {
        case ..<0.42:
            let state: ItemState = random.pick([.open, .open, .open, .draft, .merged, .closed])
            return Item(
                kind: .pullRequest,
                repository: repository,
                number: number,
                title: random.pick(prTitles) + " " + random.pick(subjects),
                url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
                author: random.pick(authors),
                authorKind: .me,
                state: state,
                checks: random.pick([.passed, .passed, .pending, .failed, .none]),
                createdAt: created,
                updatedAt: updated,
                closedAt: state.isOpen ? nil : updated,
                activity: random.int(12),
                details: ItemDetails(
                    headBranch: random.pick(branches),
                    baseBranch: "main",
                    additions: random.int(900),
                    deletions: random.int(400),
                    changedFiles: random.int(30) + 1,
                    review: random.pick([nil, .approved, .reviewRequired, .changesRequested]),
                    comments: random.int(8),
                    reviews: random.int(3)
                )
            )
        case ..<0.68:
            let state: ItemState = random.pick([.open, .open, .open, .closed])
            return Item(
                kind: .issue,
                repository: repository,
                number: number,
                title: random.pick(issuePrefixes) + random.pick(issueTitles) + " " + random.pick(subjects),
                url: URL(string: "https://github.com/\(repository)/issues/\(number)")!,
                author: random.pick(authors),
                authorKind: .me,
                state: state,
                createdAt: created,
                updatedAt: updated,
                closedAt: state.isOpen ? nil : updated,
                activity: random.int(6),
                details: ItemDetails(comments: random.int(6))
            )
        case ..<0.82:
            let state: ItemState = random.pick([.running, .succeeded, .succeeded, .failed])
            let branch = random.pick(branches)
            return Item(
                kind: .workflowRun,
                repository: repository,
                number: 9_000 + number,
                title: random.pick(workflows),
                url: URL(string: "https://github.com/\(repository)/actions/runs/\(9_000_000 + number)")!,
                author: random.pick(authors),
                authorKind: .me,
                state: state,
                checks: state == .running ? .pending : state == .failed ? .failed : .passed,
                createdAt: created,
                updatedAt: updated,
                closedAt: state == .running ? nil : updated,
                branch: branch,
                details: ItemDetails(runTitle: random.pick(prTitles) + " " + random.pick(subjects), runEvent: random.pick(["push", "pull_request", "schedule"]), runAttempt: 1)
            )
        case ..<0.94:
            let id = "\(project)-ping-\(index)"
            var item = Ping(
                id: id,
                title: random.pick(pingTitles),
                projects: [project],
                sent: created,
                repository: repository,
                body: random.chance(0.5) ? random.pick(pingBodies) : nil,
                sender: random.pick(senders),
                action: random.pick([.url(URL(string: "https://github.com/\(repository)/pull/\(number)")!), .app("Ghostty"), .herdr("w1:t\(index % 9 + 1)")])
            ).item
            item.number = index + 1
            return item
        default:
            return Note(
                id: "\(project)-note-\(index)",
                url: URL(string: "https://www.notion.so/\(project)-\(index)")!,
                number: index + 1,
                prefix: String(project.prefix(3)).uppercased(),
                title: random.pick(noteTitles),
                labels: random.chance(0.5) ? [random.pick(["idea", "bug", "design", "later"])] : [],
                status: Note.open,
                created: created,
                edited: updated
            ).item
        }
    }

    // MARK: - Words

    static let authors = ["yahyabedirhan", "octocat", "renovate[bot]", "mona", "hubot", "dependabot[bot]"]
    static let senders = ["claude", "codex", "cursor", "gemini", "opencode", "deploy-bot", "claude code"]
    static let branches = ["main", "feat/tabs-strip", "fix/row-heights", "chore/deps", "feat/notes-sync", "fix/rate-limit-banner", "refactor/arrangement"]
    static let workflows = ["CI", "linux cli", "release", "lint", "docs", "nightly"]
    static let prTitles = ["feat: add", "fix: handle", "refactor: split", "chore: bump", "docs: explain", "perf: cache", "test: cover"]
    static let issuePrefixes = ["", "bug: ", "spec: ", "qa: ", "ticket: "]
    static let issueTitles = ["slow scroll in", "crash when opening", "support for", "wrong count in", "missing state for", "stale cache of"]
    static let subjects = [
        "the tab strip", "pull request rows", "the All tab", "workflow run polling", "note sync with Notion",
        "the rate-limit footer", "hover cards", "keyboard navigation", "the menu bar label",
        "remote machine pings", "the configuration reader", "seen records", "the onboarding flow",
        "project grouping by repository and by author when many repositories share one owner",
    ]
    static let pingTitles = [
        "PR ready for review", "Need your input on the schema", "Tests are green", "Blocked on a secret",
        "Release notes drafted", "Spec ready", "QA build installed", "Decision needed: cache size",
    ]
    static let pingBodies = ["Pick A or B in the pane.", "The run took 4 min.", "Merged into the effort branch."]
    static let noteTitles = ["Try a denser row", "Ask about the release cadence", "Tab order should follow recency", "Look at lazy stacks", "Idea: per-tab search"]
}

/// A small deterministic generator (SplitMix64), so fixtures repeat.
public struct SeededRandom {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func int(_ upper: Int) -> Int { upper <= 0 ? 0 : Int(next() % UInt64(upper)) }
    public mutating func chance(_ share: Double) -> Bool { double() < share }
    public mutating func pick<T>(_ values: [T]) -> T { values[int(values.count)] }
}
