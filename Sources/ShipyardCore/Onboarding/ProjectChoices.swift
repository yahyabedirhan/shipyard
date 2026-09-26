import Foundation

/// What the user has picked so far in the project picker: the repositories
/// offered (the ones they typed, then the suggestions), the ones chosen, and
/// the project each chosen one goes into. Pure, so the picker's rules are
/// tested without SwiftUI.
///
/// Naming and grouping are one thing: each chosen repository carries a
/// project name, and the repositories that share a name make one project.
public struct ProjectChoices: Equatable, Sendable {
    /// A chosen repository and the name of the project it goes into.
    public struct Choice: Equatable, Sendable, Identifiable {
        public var repository: RepoSummary
        /// As typed; it's trimmed when projects are made.
        public var project: String
        /// The repository's slug.
        public var id: String { repository.slug }
        /// The project name as it's written: `project`, trimmed.
        public var name: String { ProjectChoices.trimmed(project) }
    }

    /// The chosen repositories, in the order they were chosen.
    public private(set) var chosen: [Choice] = []
    private var suggestions: [RepoSummary]
    private var typed: [RepoSummary] = []

    public init(suggestions: [RepoSummary] = []) {
        self.suggestions = suggestions
    }

    /// The repositories the picker lists: those typed that aren't among the
    /// suggestions (first, so one just added is in sight), then the suggestions.
    public var offered: [RepoSummary] {
        typed.filter { repository in !suggestions.contains { Self.same($0.slug, repository.slug) } } + suggestions
    }

    /// The suggestions, when they arrive after the user started typing.
    public mutating func setSuggestions(_ suggestions: [RepoSummary]) {
        self.suggestions = suggestions
    }

    /// A repository the user typed (and GitHub accepted): listed before the
    /// suggestions, and chosen. One already listed is only chosen.
    public mutating func add(_ repository: RepoSummary) {
        let listed = offered.first { Self.same($0.slug, repository.slug) }
        if listed == nil { typed.append(repository) }
        if !isChosen(repository.slug) { toggle(listed ?? repository) }
    }

    /// Whether the repository `slug` is chosen (GitHub's names aren't case-sensitive).
    public func isChosen(_ slug: String) -> Bool {
        index(of: slug) != nil
    }

    /// The chosen repository `slug` and its project name; `nil` when it isn't chosen.
    public func choice(for slug: String) -> Choice? {
        index(of: slug).map { chosen[$0] }
    }

    /// Chooses `repository`, or unchooses it when it's chosen.
    public mutating func toggle(_ repository: RepoSummary) {
        if let index = index(of: repository.slug) {
            chosen.remove(at: index)
        } else {
            chosen.append(Choice(repository: repository, project: defaultName(for: repository)))
        }
    }

    /// Puts the chosen repository `slug` into the project named `name`:
    /// a new name renames its project, another project's name groups it there.
    public mutating func rename(_ slug: String, to name: String) {
        guard let index = index(of: slug) else { return }
        chosen[index].project = name
    }

    /// The projects' names, once each, in order: what a repository can be grouped with.
    public var projectNames: [String] {
        projects.map(\.name)
    }

    /// The projects to add: one per distinct name, in the order each name
    /// was first chosen, each with its repositories in the order chosen.
    public var projects: [NewProject] {
        var result: [NewProject] = []
        for choice in chosen {
            if let index = result.firstIndex(where: { $0.name == choice.name }) {
                result[index].repositories.append(choice.repository.slug)
            } else {
                result.append(NewProject(name: choice.name, repositories: [choice.repository.slug]))
            }
        }
        return result
    }

    /// Whether Add can write the choices: something chosen, every project named.
    public var canConfirm: Bool {
        !chosen.isEmpty && !hasUnnamedProject
    }

    /// Whether a chosen repository's project name is empty, which Add waits on.
    public var hasUnnamedProject: Bool {
        chosen.contains { $0.name.isEmpty }
    }

    // MARK: - Private

    private func index(of slug: String) -> Int? {
        chosen.firstIndex { Self.same($0.repository.slug, slug) }
    }

    /// GitHub's names aren't case-sensitive.
    private static func same(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }

    /// The repository's name without its owner, or `owner/name` when a
    /// project already has that name, so choosing never groups by accident.
    private func defaultName(for repository: RepoSummary) -> String {
        let name = String(repository.slug.split(separator: "/").last ?? Substring(repository.slug))
        return projectNames.contains(name) ? repository.slug : name
    }

    fileprivate static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }
}
