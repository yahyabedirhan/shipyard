import Foundation
import ShipyardConfig

/// A demo run's example items, from `demo-items.json` in the demo folder:
/// the account the header shows, each repository's pull requests, issues
/// and workflow runs, and each project's notes. A demo run with this file
/// lists them in place of GitHub's and Notion's, and sends no request,
/// so a screenshot shows made-up content (`Shipyard`'s `demoItems`).
///
/// Ages are written as how long ago (`"25m"`, `"3h"`, `"2d"`) and counted
/// back from when the file was read, so the file never goes stale.
/// A file that doesn't read is kept as its problem: every refresh fails
/// with it, rather than falling back to the user's own GitHub.
public struct DemoItems: Sendable {
    /// The file's name in the demo folder.
    public static let fileName = "demo-items.json"

    struct Repository: Sendable {
        var slug: String
        var items: [Item]
        var branches: RunBranches
    }

    private let content: Result<Content, DemoItemsError>

    struct Content: Sendable {
        var viewer: Viewer
        var repositories: [Repository]
        /// Each project's notes, by project title, as Notion keys them.
        var notes: [String: [Note]]
    }

    init(_ content: Content) {
        self.content = .success(content)
    }

    init(problem: DemoItemsError) {
        content = .failure(problem)
    }

    /// The example items in `folder`'s `demo-items.json`, with every age
    /// counted back from `now`; `nil` when the folder has no such file.
    public static func read(in folder: URL, at now: Date) -> DemoItems? {
        let url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decode(Data(contentsOf: url), folder: folder, at: now)
        } catch {
            return DemoItems(problem: DemoItemsError("can't read it: \(error.localizedDescription)"))
        }
    }

    /// The items `data` describes; a file that doesn't read is kept as
    /// its problem. Avatar paths resolve against `folder`.
    static func decode(_ data: Data, folder: URL, at now: Date) -> DemoItems {
        do {
            let file = try JSONDecoder().decode(DemoFile.self, from: data)
            return DemoItems(try file.content(folder: folder, at: now))
        } catch let error as DemoItemsError {
            return DemoItems(problem: error)
        } catch let error as DecodingError {
            return DemoItems(problem: DemoItemsError(error))
        } catch {
            return DemoItems(problem: DemoItemsError(error.localizedDescription))
        }
    }

    /// Why the file doesn't read, when it doesn't.
    public var problem: DemoItemsError? {
        if case .failure(let problem) = content { return problem }
        return nil
    }

    private func loaded() throws -> Content {
        switch content {
        case .success(let content): return content
        case .failure(let problem): throw GitHubError.graphQL("the demo's \(Self.fileName) doesn't read: \(problem.message)")
        }
    }

    private func entry(_ slug: String) -> Repository? {
        guard case .success(let content) = content else { return nil }
        return content.repositories.first { $0.slug.lowercased() == slug.lowercased() }
    }

    /// Each project's notes, by project slug, for the projects given by
    /// slug and title: the notes the file lists under the project's title.
    func notes(for projects: [(slug: String, title: String)]) -> NotesReading {
        switch content {
        case .failure(let problem):
            return .failed(.unreadable("\(Self.fileName): \(problem.message)"))
        case .success(let content):
            var read: [String: Result<[Note], NotionError>] = [:]
            for (slug, title) in projects {
                read[slug] = .success(content.notes[title] ?? [])
            }
            return .read(read)
        }
    }
}

extension DemoItems: GitHubReading {
    func viewer() async throws -> Viewer {
        try loaded().viewer
    }

    func recentRepositories(at now: Date) async throws -> [RepoSummary] {
        try loaded().repositories.map { RepoSummary(slug: $0.slug) }
    }

    func repository(_ slug: String) async throws -> RepoSummary {
        _ = try loaded()
        guard let repository = entry(slug) else { throw GitHubError.http(404) }
        return RepoSummary(slug: repository.slug)
    }

    func repositories(of lookup: RepositoryLookup, at now: Date) async throws -> [RepoSummary]? {
        let repositories = try loaded().repositories.map { RepoSummary(slug: $0.slug) }
        switch lookup {
        case .owner(let owner):
            let owned = repositories.filter { $0.slug.lowercased().hasPrefix(owner.lowercased() + "/") }
            return owned.isEmpty ? nil : owned
        case .group:
            return repositories
        }
    }

    /// Every project's items from the file, as `GitHubClient.fetch` would
    /// list them: each repository the project watches, the kinds it shows,
    /// its runs on the branches its `branches` allows, and the review
    /// requested of the viewer. No rate limit is reported.
    func fetch(projects configured: [ProjectSettings], resolved: [String: ResolvedRepositories], at fetchedAt: Date) async throws -> Snapshot {
        let content = try loaded()
        let projects = configured.map { $0.resolved(by: resolved[$0.slug]) }
        let pullRequests = content.repositories.flatMap(\.items).filter { $0.kind == .pullRequest }
        let reviewRequested = Set(pullRequests.filter(\.reviewRequestedFromViewer).map(\.id))
        let searchPullRequests = pullRequests.filter { $0.reviewRequestedFromViewer && $0.state.isOpen }
        var items: [String: [Item]] = [:]
        for project in projects {
            var listed: [Item] = []
            for slug in project.repositorySlugs {
                guard let repository = entry(slug) else { continue }
                var found = repository.items.filter { $0.kind != .workflowRun && project.shows($0.kind) }
                if project.workflowRuns.show {
                    let runs = repository.items.filter { $0.kind == .workflowRun }
                    found += WorkflowRuns.filter(runs, branches: project.workflowRuns.branches, known: repository.branches)
                }
                listed += found.map { item in
                    var item = item
                    item.repository = slug
                    return item
                }
            }
            if project.usesAnywhere {
                let ids = Set(listed.map(\.id))
                listed += searchPullRequests.filter { !ids.contains($0.id) }
            }
            items[project.slug] = listed
        }
        return Snapshot(
            fetchedAt: fetchedAt,
            items: items,
            viewerLogin: content.viewer.login,
            reviewRequested: reviewRequested,
            searchPullRequests: searchPullRequests,
            repositories: Dictionary(projects.map { ($0.slug, $0.repositorySlugs) }, uniquingKeysWith: { first, _ in first })
        )
    }
}

/// Why a demo run's `demo-items.json` doesn't read.
public struct DemoItemsError: Error, Equatable, Sendable {
    public var message: String

    init(_ message: String) {
        self.message = message
    }

    init(_ error: DecodingError) {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return keys.isEmpty ? "" : "at \(keys.hasPrefix(".") ? String(keys.dropFirst()) : keys): "
        }
        switch error {
        case .keyNotFound(let key, let context):
            message = "\(path(context))`\(key.stringValue)` is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            message = "\(path(context))\(context.debugDescription)"
        case .dataCorrupted(let context):
            message = "\(path(context))\(context.debugDescription)"
        @unknown default:
            message = "\(error)"
        }
    }
}

/// The file as written. Every age is how long ago, `<number><unit>` with
/// `m`, `h`, `d` or `w`.
private struct DemoFile: Decodable {
    var account: Account
    var repositories: [String: RepositoryEntry]
    var notes: [String: [NoteEntry]]?

    struct Account: Decodable {
        var login: String
        var name: String?
        /// An image file, relative to the demo folder.
        var avatar: String?
    }

    struct RepositoryEntry: Decodable {
        var defaultBranch: String?
        var pullRequests: [PullRequestEntry]?
        var issues: [IssueEntry]?
        var runs: [RunEntry]?
    }

    struct PullRequestEntry: Decodable {
        var number: Int
        var title: String
        var author: String
        var state: String
        var checks: ChecksState?
        var review: String?
        var reviewRequested: Bool?
        var branch: String?
        var base: String?
        var additions: Int?
        var deletions: Int?
        var files: Int?
        var comments: Int?
        var reviews: Int?
        var age: Age
        var updated: Age?
        var closed: Age?
    }

    struct IssueEntry: Decodable {
        var number: Int
        var title: String
        var author: String
        var state: String
        var comments: Int?
        var age: Age
        var updated: Age?
        var closed: Age?
    }

    struct RunEntry: Decodable {
        var workflow: String
        var number: Int
        var branch: String
        var state: String
        var actor: String
        var title: String?
        var event: String?
        var age: Age
        var updated: Age?
    }

    struct NoteEntry: Decodable {
        var number: NoteNumber?
        var title: String
        var labels: [String]?
        var age: Age
    }

    func content(folder: URL, at now: Date) throws -> DemoItems.Content {
        let login = account.login
        let viewer = Viewer(
            login: login,
            id: 1,
            name: account.name,
            avatarURL: account.avatar.map { folder.appendingPathComponent($0) }
        )
        var repositories: [DemoItems.Repository] = []
        for (slug, entry) in self.repositories.sorted(by: { $0.key < $1.key }) {
            guard slug.split(separator: "/").count == 2 else {
                throw DemoItemsError("`\(slug)` isn't a repository: write it as owner/name")
            }
            var items: [Item] = []
            for pullRequest in entry.pullRequests ?? [] {
                items.append(try pullRequest.item(in: slug, viewer: login, at: now))
            }
            for issue in entry.issues ?? [] {
                items.append(try issue.item(in: slug, viewer: login, at: now))
            }
            for run in entry.runs ?? [] {
                items.append(try run.item(in: slug, viewer: login, at: now))
            }
            let heads = items.filter { $0.kind == .pullRequest && $0.state.isOpen }.compactMap(\.details.headBranch)
            repositories.append(DemoItems.Repository(
                slug: slug,
                items: items,
                branches: RunBranches(defaultBranch: entry.defaultBranch ?? "main", pullRequestHeads: Set(heads))
            ))
        }
        var notes: [String: [Note]] = [:]
        for (project, entries) in self.notes ?? [:] {
            notes[project] = entries.enumerated().map { index, entry in entry.note(project: project, index: index, at: now) }
        }
        return DemoItems.Content(viewer: viewer, repositories: repositories, notes: notes)
    }
}

extension DemoFile.PullRequestEntry {
    func item(in repository: String, viewer: String, at now: Date) throws -> Item {
        let states: [String: ItemState] = ["open": .open, "draft": .draft, "merged": .merged, "closed": .closed]
        guard let state = states[self.state] else {
            throw DemoItemsError("\(repository) pull request \(number): `state` is open, draft, merged or closed, not `\(self.state)`")
        }
        let reviews: [String: ReviewDecision] = [
            "approved": .approved, "changes-requested": .changesRequested, "review-required": .reviewRequired,
        ]
        let decision = try review.map { review in
            guard let decision = reviews[review] else {
                throw DemoItemsError("\(repository) pull request \(number): `review` is approved, changes-requested or review-required, not `\(review)`")
            }
            return decision
        }
        let dates = DemoFile.Dates(age: age, updated: updated, closed: closed, finished: !state.isOpen, at: now)
        return Item(
            kind: .pullRequest,
            repository: repository,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
            author: author,
            authorKind: DemoFile.authorKind(author, viewer: viewer),
            state: state,
            checks: checks ?? .none,
            reviewRequestedFromViewer: (reviewRequested ?? false) && state.isOpen,
            createdAt: dates.created,
            updatedAt: dates.updated,
            closedAt: dates.closed,
            activity: (comments ?? 0) + (self.reviews ?? 0),
            details: ItemDetails(
                headBranch: branch,
                baseBranch: base ?? "main",
                additions: additions,
                deletions: deletions,
                changedFiles: files,
                review: decision,
                comments: comments ?? 0,
                reviews: self.reviews ?? 0
            )
        )
    }
}

extension DemoFile.IssueEntry {
    func item(in repository: String, viewer: String, at now: Date) throws -> Item {
        let states: [String: ItemState] = ["open": .open, "closed": .closed]
        guard let state = states[self.state] else {
            throw DemoItemsError("\(repository) issue \(number): `state` is open or closed, not `\(self.state)`")
        }
        let dates = DemoFile.Dates(age: age, updated: updated, closed: closed, finished: !state.isOpen, at: now)
        return Item(
            kind: .issue,
            repository: repository,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repository)/issues/\(number)")!,
            author: author,
            authorKind: DemoFile.authorKind(author, viewer: viewer),
            state: state,
            createdAt: dates.created,
            updatedAt: dates.updated,
            closedAt: dates.closed,
            activity: comments ?? 0,
            details: ItemDetails(comments: comments ?? 0)
        )
    }
}

extension DemoFile.RunEntry {
    func item(in repository: String, viewer: String, at now: Date) throws -> Item {
        let states: [String: (ItemState, ChecksState)] = [
            "running": (.running, .pending), "succeeded": (.succeeded, .passed), "failed": (.failed, .failed),
        ]
        guard let result = states[self.state] else {
            throw DemoItemsError("\(repository) run \(number): `state` is running, succeeded or failed, not `\(self.state)`")
        }
        let (state, checks) = result
        let dates = DemoFile.Dates(age: age, updated: updated, closed: nil, finished: state != .running, at: now)
        return Item(
            kind: .workflowRun,
            repository: repository,
            number: number,
            title: workflow,
            url: URL(string: "https://github.com/\(repository)/actions/runs/\(number)")!,
            author: actor,
            authorKind: DemoFile.authorKind(actor, viewer: viewer),
            state: state,
            checks: checks,
            createdAt: dates.created,
            updatedAt: dates.updated,
            closedAt: dates.closed,
            branch: branch,
            details: ItemDetails(runTitle: title, runEvent: event ?? "push", runAttempt: 1)
        )
    }
}

extension DemoFile.NoteEntry {
    func note(project: String, index: Int, at now: Date) -> Note {
        let created = now.addingTimeInterval(-age.seconds)
        let key = "\(project)-\(index + 1)".lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return Note(
            id: "demo-note-\(String(key))",
            url: URL(string: "https://www.notion.so/demo-note-\(String(key))")!,
            number: number?.number,
            prefix: number?.prefix,
            title: title,
            labels: labels ?? [],
            status: Note.open,
            created: created,
            edited: created
        )
    }
}

extension DemoFile {
    static func authorKind(_ login: String, viewer: String) -> AuthorKind {
        if login.hasSuffix("[bot]") { return .bot }
        return login.lowercased() == viewer.lowercased() ? .me : .other
    }

    /// An item's dates from its ages: created `age` ago, updated `updated`
    /// ago (else when created), and, once finished, closed `closed` ago
    /// (else when last updated).
    struct Dates {
        var created: Date
        var updated: Date
        var closed: Date?

        init(age: Age, updated: Age?, closed: Age?, finished: Bool, at now: Date) {
            created = now.addingTimeInterval(-age.seconds)
            self.updated = now.addingTimeInterval(-(updated ?? age).seconds)
            self.closed = finished ? now.addingTimeInterval(-(closed ?? updated ?? age).seconds) : nil
        }
    }

    /// How long ago, written `<number><unit>`: `m`inutes, `h`ours, `d`ays
    /// or `w`eeks.
    struct Age: Decodable {
        var seconds: TimeInterval

        private static let units: [Character: TimeInterval] = ["m": 60, "h": 3600, "d": 86_400, "w": 604_800]

        init(from decoder: any Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let unit = text.last.flatMap({ Self.units[$0] }), let number = Int(text.dropLast()), number >= 0 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "`\(text)` isn't an age: write how long ago as a number and m, h, d or w, such as \"25m\""
                ))
            }
            seconds = TimeInterval(number) * unit
        }
    }

    /// A note's number: `14`, or with its project's prefix, `"SHIP-14"`.
    struct NoteNumber: Decodable {
        var prefix: String?
        var number: Int

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                self.number = number
                return
            }
            let text = try container.decode(String.self)
            let parts = text.split(separator: "-")
            guard parts.count == 2, let number = Int(parts[1]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "`\(text)` isn't a note number: write 14 or \"SHIP-14\""
                ))
            }
            prefix = String(parts[0])
            self.number = number
        }
    }
}
