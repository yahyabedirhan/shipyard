import Foundation

/// The themes embedded in the app, read from their files' text once, on
/// first use.
public enum BuiltInThemes {
    /// Each built-in file's name and text, in the order themes are listed.
    static let sources: [(file: String, text: String)] = [
        ("Shipyard.toml", shipyardSource),
        ("Native.toml", nativeSource),
        ("Graphite.toml", graphiteSource),
        ("Paper.toml", paperSource),
        ("Midnight.toml", midnightSource),
        ("Harbor.toml", harborSource),
    ]

    /// Each built-in file parsed, for user themes to extend.
    public static let definitions: [ThemeDefinition] = read.definitions

    /// Every built-in theme, ready to draw with.
    public static let themes: [Theme] = read.themes

    /// What's wrong with the built-in files; empty unless a shipped file is broken.
    public static let issues: [ThemeIssue] = read.issues

    /// The default theme, Shipyard. Were its file ever broken, every token
    /// draws its system colour, so the app still draws.
    public static let shipyard: Theme = named("Shipyard") ?? Theme(name: "Shipyard") { _, _ in .system }

    /// The built-in theme called `name`, ignoring case.
    public static func named(_ name: String) -> Theme? {
        themes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static let read: (definitions: [ThemeDefinition], themes: [Theme], issues: [ThemeIssue]) = {
        var definitions: [ThemeDefinition] = []
        var issues: [ThemeIssue] = []
        for source in sources {
            let parsed = ThemeReader.definition(source.text, file: source.file, source: .builtIn)
            if let definition = parsed.definition { definitions.append(definition) }
            issues += parsed.issues
        }
        let resolved = ThemeReader.resolve(definitions)
        return (definitions, resolved.themes, issues + resolved.issues)
    }()
}
