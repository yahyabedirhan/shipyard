import Foundation

/// Where app control's socket is: `control.sock` in the app's support
/// folder (`SupportFolder.app`), the user's own (mode 0600), there only
/// while the app runs.
public enum ControlSocket {
    public static let fileName = "control.sock"

    /// The socket the app listens on, in its support folder `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The socket the `shipyard` command asks the running app through,
    /// given the support folder it knows. It's the folder's own today; a
    /// run whose app keeps its data elsewhere is found from here, so every
    /// command (`app open`'s wait included) looks in one place.
    public static func locate(support: URL) -> URL {
        url(in: support)
    }
}
