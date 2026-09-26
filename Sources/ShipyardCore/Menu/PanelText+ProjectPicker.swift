import Foundation

// The project picker's words (`ProjectPicker`).
extension PanelText {
    public static let pickerTitle = "Pick your projects"
    public static let pickerIntro = "Each repository you choose is a project, one section in the list. Give several the same project name to group them into one."
    /// The field for a repository that isn't suggested.
    public static let typeRepository = "owner/name or a github.com link"
    public static let findingSuggestions = "Finding the repositories you worked on recently…"
    public static let noSuggestions = "You haven't pushed to any repository lately. Add one by name above."
    /// Said while a chosen repository's project name is empty; Add waits for it.
    public static let unnamedProject = "Give every project a name."
    /// Said when Add wrote the projects but the file around them doesn't load.
    public static let addedToBrokenFile = "Added to config.toml, but the file has an error (see above). Shipyard picks the projects up once it's fixed."

    /// Why the suggestions didn't load; typing a repository still works.
    public static func suggestionsFailed(_ error: GitHubError) -> String {
        "Couldn't load suggestions: \(fetchError(error))"
    }

    /// Why Add couldn't write the file.
    public static func couldNotWrite(_ reason: String) -> String {
        "Couldn't write config.toml: \(reason)"
    }

    /// The picker's confirm button: "Add 2 projects".
    public static func addProjects(_ count: Int) -> String {
        switch count {
        case 0: "Add projects"
        case 1: "Add 1 project"
        default: "Add \(count) projects"
        }
    }

    /// What Add writes, above its button: "Adds e-commerce (2 repositories),
    /// job-search"; `nil` while nothing is chosen.
    public static func pickedProjects(_ projects: [NewProject]) -> String? {
        guard !projects.isEmpty else { return nil }
        let names = projects.map { project in
            project.repositories.count > 1 ? "\(project.name) (\(project.repositories.count) repositories)" : project.name
        }
        return "Adds " + names.joined(separator: ", ")
    }
}
