import ShipyardCore
import SwiftUI

/// Onboarding's project step, shown while `phase` is `needsProjects`: the
/// repositories the user was active in recently (`suggestedRepositories()`),
/// a field to add any other by `owner/name` or link (`checkRepository(_:)`),
/// and a project name under each chosen one. Chosen repositories given the
/// same name are grouped into one project. Add writes them to the
/// configuration (`addProjects(_:)`), which moves shipyard to `ready`: the
/// panel shows the list without a restart. The rules live in `ProjectChoices`.
///
/// After a preset that needs repositories (`PresetPicker`), Add writes the
/// preset with them instead (`add`), and a back button returns to the presets.
struct ProjectPicker: View {
    let shipyard: Shipyard
    /// The preset the repositories are for; `nil` for the plain picker.
    var preset: Preset?
    /// What Add does with the projects; `nil` appends them (`addProjects`).
    var add: (([NewProject]) async throws -> ConfigStore.ReloadResult)?
    /// Back to the presets; `nil` for the plain picker.
    var back: (() -> Void)?

    private enum Suggestions {
        case loading
        case loaded
        case failed(String)
    }

    /// The tallest the repository list gets before it scrolls.
    private static let maxListHeight: CGFloat = 300

    @State private var choices = ProjectChoices()
    @State private var suggestions = Suggestions.loading
    @State private var typed = ""
    @State private var isChecking = false
    @State private var rejection: String?
    @State private var isAdding = false
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let back, let preset {
                    HStack(spacing: 6) {
                        Button(action: back) {
                            Label(PanelText.backToPresets, systemImage: "chevron.left")
                        }
                        .buttonStyle(TextButtonStyle())
                        .disabled(isAdding)
                        Text(preset.title)
                            .font(TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(PanelText.pickerTitle).font(TypeScale.display)
                Text(PanelText.pickerIntro)
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            addField
            repositories
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadSuggestions() }
    }

    // MARK: - Adding by name

    private var addField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(PanelText.typeRepository, text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(check)
                if isChecking {
                    ProgressView().controlSize(.small)
                }
                Button("Add", action: check)
                    .buttonStyle(PillButtonStyle())
                    .disabled(isTypedEmpty || isChecking)
            }
            if let rejection {
                Text(LocalizedStringKey(rejection))
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: typed) { rejection = nil }
    }

    private var isTypedEmpty: Bool {
        typed.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func check() {
        let text = typed
        guard !isTypedEmpty, !isChecking else { return }
        isChecking = true
        rejection = nil
        Task {
            let result = await shipyard.checkRepository(text)
            isChecking = false
            switch result {
            case .accepted(let repository):
                choices.add(repository)
                typed = ""
            case .rejected(let reason):
                rejection = reason.message
            }
        }
    }

    // MARK: - The list

    @ViewBuilder
    private var repositories: some View {
        switch suggestions {
        case .loading where choices.offered.isEmpty:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(PanelText.findingSuggestions)
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message) where choices.offered.isEmpty:
            failed(message)
        default:
            VStack(alignment: .leading, spacing: 4) {
                if case .failed(let message) = suggestions { failed(message) }
                if choices.offered.isEmpty {
                    Text(PanelText.noSuggestions)
                        .font(TypeScale.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    list
                }
            }
        }
    }

    private func failed(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await loadSuggestions() } }
                .buttonStyle(TextButtonStyle())
        }
    }

    /// Scrolls inside a measured height, like the menu's list.
    private var list: some View {
        MeasuredScrollView(maxHeight: Self.maxListHeight) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(choices.offered.enumerated()), id: \.element.id) { index, repository in
                    if index > 0 { Hairline().padding(.leading, 28) }
                    row(repository)
                }
            }
            .padding(.vertical, 2)
        }
        .card()
    }

    private func row(_ repository: RepoSummary) -> some View {
        let choice = choices.choice(for: repository.slug)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { choice != nil },
                set: { _ in choices.toggle(repository) }
            )) {
                HStack(spacing: 4) {
                    Text(repository.slug)
                        .font(choice != nil ? TypeScale.bodyEmphasis : TypeScale.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if repository.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            // No hover help: the lock says private.
                            .accessibilityLabel("Private")
                    }
                }
            }
            .toggleStyle(.checkbox)
            if let choice {
                projectName(choice)
                    .padding(.leading, 20)
            } else if let description = repository.description, !description.isEmpty {
                Text(description)
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(choice != nil ? Palette.accent.opacity(0.06) : .clear)
        .animation(Motion.hover, value: choice != nil)
    }

    /// The chosen repository's project name, and a menu that groups it with
    /// another project by taking that project's name.
    private func projectName(_ choice: ProjectChoices.Choice) -> some View {
        let others = choices.projectNames.filter { $0 != choice.name }
        return HStack(spacing: 6) {
            Text("Project")
                .font(TypeScale.meta)
                .foregroundStyle(.secondary)
            TextField("Project name", text: Binding(
                get: { choice.project },
                set: { choices.rename(choice.id, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            if !others.isEmpty {
                Menu("Group with") {
                    ForEach(others, id: \.self) { name in
                        Button(name) { choices.rename(choice.id, to: name) }
                    }
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    // MARK: - Adding

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            let projects = choices.projects
            if let summary = PanelText.pickedProjects(projects) {
                Text(summary)
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if choices.hasUnnamedProject {
                    Text(PanelText.unnamedProject).font(TypeScale.caption).foregroundStyle(Palette.red)
                }
                Spacer()
                if isAdding {
                    ProgressView().controlSize(.small)
                }
                Button(PanelText.addProjects(projects.count), action: confirm)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!choices.canConfirm || isAdding)
            }
            if let addError {
                Text(addError)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func confirm() {
        guard choices.canConfirm, !isAdding else { return }
        isAdding = true
        addError = nil
        Task {
            defer { isAdding = false }
            do {
                // With projects, the phase moves to `ready` and the panel
                // swaps this view for the list.
                let result = if let add {
                    try await add(choices.projects)
                } else {
                    try await shipyard.addProjects(choices.projects)
                }
                if case .invalid = result {
                    // Written, but the file around them doesn't load: the
                    // banner above says why. Don't write them twice.
                    choices = ProjectChoices(suggestions: choices.offered)
                    addError = PanelText.addedToBrokenFile
                }
            } catch let error as ConfigError {
                addError = error.description
            } catch {
                addError = PanelText.couldNotWrite(error.localizedDescription)
            }
        }
    }

    private func loadSuggestions() async {
        suggestions = .loading
        do {
            choices.setSuggestions(try await shipyard.suggestedRepositories())
            suggestions = .loaded
        } catch let error as GitHubError {
            suggestions = .failed(PanelText.suggestionsFailed(error))
        } catch {
            suggestions = .failed(PanelText.suggestionsFailed(.network(error.localizedDescription)))
        }
    }
}
