import Foundation

/// What the `shipyard` command asks of the running app: one request per
/// connection over `control.sock`. On the wire it's one JSON object naming
/// the protocol's `version` and the `command`, with the command's own
/// fields beside them:
///
///     {"version":1,"command":"app.status","json":true}
///
/// The wire format is a contract between a `shipyard` and the app of the
/// same build. A new request is a case here, its `command` name and its
/// fields in `Wire`.
public enum ControlRequest: Equatable, Sendable {
    /// `shipyard app status [--json]`: the status as lines, or as one JSON
    /// object (`AppStatus`).
    case appStatus(json: Bool)
    /// `shipyard app quit`: the app replies, then quits.
    case appQuit
    /// `shipyard panel open`: the menu bar icon's panel on screen.
    case panelOpen
    /// `shipyard panel close`.
    case panelClose
    /// `shipyard panel fold <project>`: the project's section collapsed.
    case panelFold(project: String)
    /// `shipyard panel unfold <project>`.
    case panelUnfold(project: String)
    /// `shipyard panel show-more <project> <kind>`: every row of the
    /// project's group of that kind, past its `show-first` cap. The kind is
    /// as the command names it (`pull-requests`); the app checks it.
    case panelShowMore(project: String, kind: String)
    /// `shipyard panel tab <name>`: the tabs layout's selected tab, a
    /// project's name or `All`.
    case panelTab(name: String)

    /// The protocol's version. A request or app of another version is
    /// refused with both numbers, never misread.
    public static let version = 1

    /// The request as one JSON object.
    public func encoded() -> Data {
        let wire: Wire
        switch self {
        case .appStatus(let json):
            wire = Wire(command: "app.status", json: json)
        case .appQuit:
            wire = Wire(command: "app.quit")
        case .panelOpen:
            wire = Wire(command: "panel.open")
        case .panelClose:
            wire = Wire(command: "panel.close")
        case .panelFold(let project):
            wire = Wire(command: "panel.fold", project: project)
        case .panelUnfold(let project):
            wire = Wire(command: "panel.unfold", project: project)
        case .panelShowMore(let project, let kind):
            wire = Wire(command: "panel.showMore", project: project, kind: kind)
        case .panelTab(let name):
            wire = Wire(command: "panel.tab", name: name)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(wire)
    }

    /// Reads a request the client sent: refused when it isn't JSON, names
    /// another version, or names a command this build doesn't know.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlRequest {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw .unreadable("the request isn't a control request")
        }
        guard wire.version == version else { throw .otherVersion(wire.version) }
        switch wire.command {
        case "app.status": return .appStatus(json: wire.json ?? false)
        case "app.quit": return .appQuit
        case "panel.open": return .panelOpen
        case "panel.close": return .panelClose
        case "panel.fold": return .panelFold(project: try wire.field(\.project, "project"))
        case "panel.unfold": return .panelUnfold(project: try wire.field(\.project, "project"))
        case "panel.showMore":
            return .panelShowMore(project: try wire.field(\.project, "project"), kind: try wire.field(\.kind, "kind"))
        case "panel.tab": return .panelTab(name: try wire.field(\.name, "name"))
        default: throw .unknownCommand(wire.command)
        }
    }

    /// Every request's fields, each optional but `version` and `command`.
    struct Wire: Codable {
        var version = ControlRequest.version
        var command: String
        var json: Bool?
        var project: String?
        var kind: String?
        var name: String?

        /// The field at `path`, which `command` needs: refused when the
        /// request leaves it out.
        func field(_ path: KeyPath<Wire, String?>, _ key: String) throws(ControlProtocolError) -> String {
            guard let value = self[keyPath: path] else {
                throw .unreadable("the control command `\(command)` needs its `\(key)`")
            }
            return value
        }
    }
}

/// Why a control request or reply doesn't read.
public enum ControlProtocolError: Error, Equatable, Sendable {
    /// It isn't the JSON object it should be.
    case unreadable(String)
    /// It speaks another version of the protocol: the `shipyard` command
    /// and the app come from different builds.
    case otherVersion(Int)
    /// Its version matches but its command doesn't exist.
    case unknownCommand(String)

    /// One line for the reply's `error`, from the app's side.
    public var message: String {
        switch self {
        case .unreadable(let why):
            return why
        case .otherVersion(let other):
            return "the shipyard command speaks control version \(other) and the app version \(ControlRequest.version): "
                + "reinstall shipyard so both come from one build"
        case .unknownCommand(let command):
            return "the app doesn't know the control command `\(command)`"
        }
    }
}
