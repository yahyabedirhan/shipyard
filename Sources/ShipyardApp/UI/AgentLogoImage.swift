import AppKit
import ShipyardCore

enum AgentLogoImage {
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Shipyard_ShipyardApp.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

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
