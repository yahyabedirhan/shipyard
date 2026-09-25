import ShipyardCore

// Placeholder for the macOS app. The menu bar app replaces this in phase 2;
// it builds only on macOS (see Package.swift).
@main
struct ShipyardApp {
    static func main() {
        print("shipyard \(ShipyardVersion.current)")
    }
}
