import Foundation
import ShipyardPings

extension Ping {
    /// The ping as a listed item: kind `ping`, with no number (0) until
    /// `Listing` gives it its section's (`PingNumbers`), always open, aged from when
    /// it was sent or last replaced, in the repository it was filed by (if any). Its URL only
    /// names it (`shipyard://ping/<id>`, or `shipyard://ping/<machine>/<id>`
    /// for a remote ping), so it never collides with a GitHub item's, nor
    /// the same id on another machine; a click runs its `action` instead. It has no GitHub author:
    /// its sender is on the ping, apart from author filters and rules.
    public var item: Item {
        Item(
            kind: .ping,
            repository: repository ?? "",
            number: 0,
            title: title,
            url: machine.map { Self.url(machine: $0, id: id) } ?? Self.url(id: id),
            author: "",
            authorKind: .other,
            state: .open,
            createdAt: sent,
            updatedAt: sent,
            ping: self
        )
    }

    /// The URL a ping's item is known by.
    public static func url(id: String) -> URL {
        URL(string: "shipyard://ping/\(id)")!
    }

    /// The URL a remote ping's item is known by: its machine's label and
    /// its id, each percent-encoded (a label may hold a space).
    public static func url(machine: String, id: String) -> URL {
        URL(string: "shipyard://ping/\(pathSegment(machine))/\(pathSegment(id))")!
    }

    /// The id a local ping's URL names; `nil` for a remote ping's URL, or
    /// any other.
    public static func id(from url: URL) -> String? {
        let path = segments(of: url)
        return path?.count == 1 ? path?.first : nil
    }

    /// The machine and id a remote ping's URL names; `nil` for a local
    /// ping's URL, or any other.
    public static func remote(from url: URL) -> (machine: String, id: String)? {
        guard let path = segments(of: url), path.count == 2 else { return nil }
        return (path[0], path[1])
    }

    private static func segments(of url: URL) -> [String]? {
        guard url.scheme == "shipyard", url.host == "ping" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        return path.isEmpty || path.contains(where: \.isEmpty) ? nil : path
    }

    private static func pathSegment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
    }
}

extension PingAction {
    /// The icon a ping's row shows for it.
    public var icon: PingIcon {
        switch self {
        case .url: .link
        case .app: .app
        case .herdr: .terminal
        }
    }
}

/// The icon a ping's row shows: what clicking it does.
public enum PingIcon: Equatable, Sendable {
    case link
    case app
    case terminal
    case noAction
}
