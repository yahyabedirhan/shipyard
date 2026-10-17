import AppKit

/// Loads a known agent's logo from the app's bundled `AgentLogos` (vector
/// PDFs, from the makers' SVGs by `make agent-logos`).
enum AgentLogoImage {
    /// The app's own `AgentLogos`, read from the repository this lab sits in
    /// (`lab/kit/UI/` is three folders under its root): a variant
    /// target declares no resources, so the lab can't bundle them.
    static let resources: Bundle = {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: root.appendingPathComponent("Sources/ShipyardApp/Resources")) ?? .main
    }()

    /// The agent's logo for light or dark mode: a `.template` logo comes back
    /// as a template image, for the view to tint. `nil` when the bundle lacks
    /// the file.
    @MainActor
    static func image(for agent: KnownAgent, dark: Bool) -> NSImage? {
        let logo = agent.logo
        let name = logo.look == .lightAndDark && dark ? logo.resource + "-dark" : logo.resource
        if let cached = cache[name] { return cached }
        guard let url = resources.url(forResource: name, withExtension: "pdf", subdirectory: "AgentLogos"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = logo.look == .template
        cache[name] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]
}
