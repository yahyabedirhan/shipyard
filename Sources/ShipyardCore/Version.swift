/// The one place shipyard's version is recorded. The app reads it from here,
/// and packaging stamps the bundle's Info.plist with the same value.
/// Versions stay below 0.1.0 until the public launch.
public enum ShipyardVersion {
    public static let current = "0.0.1"
}
