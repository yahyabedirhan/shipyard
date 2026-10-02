import AppKit
import ShipyardCore

/// Loads a known agent's logo from the app's bundled `AgentLogos` (vector
/// PDFs, from the makers' SVGs by `make agent-logos`).
enum AgentLogoImage {
    /// The bundle SwiftPM builds for the app's resources. In the app it sits
    /// in `Contents/Resources` (`make bundle` copies it there, since a bundle
    /// at the app's root breaks its signature), where SwiftPM's own
    /// `Bundle.module` doesn't look; under `swift run` and the tests,
    /// `Bundle.module` finds it beside the build.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Shipyard_ShipyardApp.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
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
