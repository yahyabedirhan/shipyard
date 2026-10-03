import Foundation
import ShipyardNotices

/// What the `shipyard` command asks of the running app: one request per
/// connection over `control.sock`, sent as a `ControlMessage` with its
/// holder. A new request is a case here, its `command` name and its fields
/// in `ControlMessage.Wire`.
public enum ControlRequest: Equatable, Sendable {
    /// `shipyard app status [--json]`: the status as lines, or as one JSON
    /// object (`AppStatus`).
    case appStatus(json: Bool)
    /// `shipyard app open` while the app runs: its status as lines, and,
    /// unlike `app.status`, leased, so the opener's lease is renewed.
    case appOpen
    /// `shipyard app quit`: the app replies with the lease the quit
    /// renewed, then quits.
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
    /// `shipyard screenshot <file.png> [--appearance light|dark]
    /// [--menu-bar-icon] [--with-indicator]`: the panel (or the menu bar
    /// icon alone) written as a PNG at `path`, absolute since the app runs
    /// in another folder; in `appearance` when it's set, as the Mac shows
    /// it otherwise. The lease's dot and banner are left out of it unless
    /// `withIndicator` keeps them.
    case screenshot(path: String, appearance: Appearance?, menuBarIcon: Bool, withIndicator: Bool)
    /// `shipyard control take [--wait <seconds>]`: the lease held until its
    /// cap. While another agent holds it, refused at once, or with
    /// `waitSeconds` (0 to `longestWait`), answered once it's this agent's
    /// or the wait runs out.
    case controlTake(waitSeconds: Int?)
    /// `shipyard control release`: the lease given up, when this agent
    /// holds it.
    case controlRelease
    /// `shipyard notify "<title>" …`: an agent's notice, shown when the
    /// user's rules select it for its project, answered with the app's
    /// verdict. Not leased: any agent may post one while another drives
    /// the app.
    case notify(Notice)

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// The protocol's version. A request or app of another version is
    /// refused with both numbers, never misread. Version 2 put the holder
    /// on every request.
    public static let version = 2

    /// The longest wait in line a `take` asks for, in seconds: an hour. It
    /// keeps the client's timeout and the app's sleep within range.
    public static let longestWait = 3600

    /// Whether the request needs the lease (`ControlLease`) before it's
    /// answered. `app.status` doesn't: it changes nothing, and reports the
    /// lease. Nor do `control.take` and `control.release`, which are the
    /// lease's own requests.
    public var isLeased: Bool {
        switch self {
        case .appStatus, .controlTake, .controlRelease, .notify: false
        default: true
        }
    }

    /// How long the app may keep the request before it answers, past the
    /// client's usual timeout: a `take`'s wait in line.
    public var wait: TimeInterval {
        if case .controlTake(let seconds?) = self { return TimeInterval(seconds) }
        return 0
    }
}

/// One request as it goes over the socket: what's asked, and who asks. On
/// the wire it's one JSON object naming the protocol's `version`, the
/// `command` and the `holder`, with the command's own fields beside them:
///
///     {"command":"app.status","holder":{"key":"…","name":"Claude Code","place":"/Users/me/shop"},"json":true,"version":2}
///
/// The wire format is a contract between a `shipyard` and the app of the
/// same build.
public struct ControlMessage: Equatable, Sendable {
    public var request: ControlRequest
    public var holder: Holder

    public init(_ request: ControlRequest, holder: Holder) {
        self.request = request
        self.holder = holder
    }

    /// The message as one JSON object.
    public func encoded() -> Data {
        var wire: Wire
        switch request {
        case .appStatus(let json):
            wire = Wire(command: "app.status", json: json)
        case .appOpen:
            wire = Wire(command: "app.open")
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
        case .screenshot(let path, let appearance, let menuBarIcon, let withIndicator):
            wire = Wire(
                command: "screenshot", path: path, appearance: appearance?.rawValue,
                menuBarIcon: menuBarIcon, withIndicator: withIndicator
            )
        case .controlTake(let waitSeconds):
            wire = Wire(command: "control.take", waitSeconds: waitSeconds)
        case .controlRelease:
            wire = Wire(command: "control.release")
        case .notify(let notice):
            wire = Wire(command: "notify", notice: notice)
        }
        wire.holder = holder
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(wire)
    }

    /// Reads a message the client sent: refused when it isn't JSON, names
    /// another version, has no holder, or names a command this build
    /// doesn't know.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw .unreadable("the request isn't a control request")
        }
        guard wire.version == ControlRequest.version else { throw .otherVersion(wire.version) }
        guard let holder = wire.holder else {
            throw .unreadable("the control command `\(wire.command)` needs its `holder`")
        }
        return ControlMessage(try request(wire), holder: holder)
    }

    /// The request `wire` names, with the fields its command needs.
    private static func request(_ wire: Wire) throws(ControlProtocolError) -> ControlRequest {
        switch wire.command {
        case "app.status": return .appStatus(json: wire.json ?? false)
        case "app.open": return .appOpen
        case "app.quit": return .appQuit
        case "panel.open": return .panelOpen
        case "panel.close": return .panelClose
        case "panel.fold": return .panelFold(project: try wire.field(\.project, "project"))
        case "panel.unfold": return .panelUnfold(project: try wire.field(\.project, "project"))
        case "panel.showMore":
            return .panelShowMore(project: try wire.field(\.project, "project"), kind: try wire.field(\.kind, "kind"))
        case "panel.tab": return .panelTab(name: try wire.field(\.name, "name"))
        case "screenshot":
            let path = try wire.field(\.path, "path")
            guard path.hasPrefix("/") else {
                throw .unreadable("the control command `screenshot` needs an absolute `path`, not `\(path)`")
            }
            var appearance: ControlRequest.Appearance?
            if let name = wire.appearance {
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    throw .unreadable("the control command `screenshot` has no appearance `\(name)`; it takes `light` or `dark`")
                }
                appearance = known
            }
            return .screenshot(
                path: path, appearance: appearance,
                menuBarIcon: wire.menuBarIcon ?? false, withIndicator: wire.withIndicator ?? false
            )
        case "control.take":
            if let seconds = wire.waitSeconds, !(0...ControlRequest.longestWait).contains(seconds) {
                throw .unreadable(
                    "the control command `control.take` needs a `waitSeconds` from 0 to \(ControlRequest.longestWait), not \(seconds)"
                )
            }
            return .controlTake(waitSeconds: wire.waitSeconds)
        case "control.release": return .controlRelease
        case "notify":
            guard let notice = wire.notice else { throw .unreadable("the control command `notify` needs its `notice`") }
            return .notify(notice)
        default: throw .unknownCommand(wire.command)
        }
    }

    /// Every request's fields, each optional but `version` and `command`.
    /// `holder` is optional here only so a request without one is refused
    /// in words.
    struct Wire: Codable {
        var version = ControlRequest.version
        var command: String
        var holder: Holder?
        var json: Bool?
        var project: String?
        var kind: String?
        var name: String?
        var path: String?
        var appearance: String?
        var menuBarIcon: Bool?
        var withIndicator: Bool?
        var waitSeconds: Int?
        /// `notify`'s notice, as one object in its own shape (`Notice`).
        var notice: Notice?

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
