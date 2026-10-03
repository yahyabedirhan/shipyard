import Foundation
import ShipyardCLISettings
import ShipyardCommand

/// A machine without the app's way for a notice request to reach the Mac,
/// chosen per request from `cli.toml`'s `[notify]`, read when the request
/// is sent so a broken file stops only `notify`. With `app-machine` set,
/// the tailnet (`TailnetNoticeRoute`), answered within about a second;
/// without it, `poll`, the herdr-shipyard plugin's hold for the Mac's poll
/// (`PluginNoticeRoute`). This is the one place the choice is made.
public struct RemoteNoticeRoute: NoticeRoute {
    private let settings: CLISettingsFile
    private let http: any NoticeHTTP
    private let poll: any NoticeRoute

    public init(settings: CLISettingsFile, http: any NoticeHTTP = URLSessionNoticeHTTP(), poll: any NoticeRoute = PluginNoticeRoute()) {
        self.settings = settings
        self.http = http
        self.poll = poll
    }

    public func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict {
        let notify: NotifySettings
        do {
            notify = try settings.read().notify
        } catch {
            return .refused(Self.reason(error))
        }
        guard let machine = notify.appMachine else { return poll.deliver(request, environment: environment) }
        return TailnetNoticeRoute(appMachine: machine, scheme: notify.scheme, port: notify.port, http: http)
            .deliver(request, environment: environment)
    }

    /// A failed read's line, without the `shipyard: ` it starts with, for
    /// `notify` to put its own in front.
    private static func reason(_ failure: CommandResult) -> String {
        var line = failure.error.trimmingCharacters(in: .newlines)
        if line.hasPrefix("shipyard: ") { line.removeFirst("shipyard: ".count) }
        return line
    }
}

/// A notice request posted straight to the app on the Mac over the user's
/// tailnet (ADR 0010): its JSON (`NoticeRequest`, a notice or a withdrawal)
/// to `<scheme>://<app-machine>:<port>/notify`, which `tailscale serve` on
/// the Mac hands to the app's listener with the sender's login. It waits
/// for the app's verdict (`TailnetWire.timeout(forBodyOf:)`); nothing is
/// queued or retried, so a Mac asleep or away is a refusal.
public struct TailnetNoticeRoute: NoticeRoute {
    public var appMachine: String
    public var scheme: NotifySettings.Scheme
    public var port: Int
    private let http: any NoticeHTTP

    public init(appMachine: String, scheme: NotifySettings.Scheme, port: Int, http: any NoticeHTTP = URLSessionNoticeHTTP()) {
        self.appMachine = appMachine
        self.scheme = scheme
        self.port = port
        self.http = http
    }

    /// Where the app machine is, without the path: `http://my-mac:47420`.
    var origin: String { "\(scheme.rawValue)://\(appMachine):\(port)" }

    public func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict {
        let showing = if case .show = request { true } else { false }
        let notDone = showing ? "this notice wasn't shown" : "the notice wasn't withdrawn"
        guard let url = URL(string: origin + TailnetWire.path) else {
            return .refused("`\(origin)` isn't a URL, so \(notDone); check [notify] in cli.toml")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let body = try? encoder.encode(request) else {
            return .refused("the request couldn't be written as JSON, so \(notDone)")
        }
        let timeout = TailnetWire.timeout(forBodyOf: body.count)
        switch http.post(body, to: url, timeout: timeout) {
        case .answered(let status, let answer):
            if let verdict = NoticeVerdict(answer: answer) { return verdict }
            return .refused("the app machine `\(appMachine)` answered HTTP \(status) without a verdict, so \(notDone); "
                + "check that shipyard runs there with [notify] listen = true, behind tailscale serve")
        case .timedOut:
            let maybe = showing ? "this notice may not have been shown" : "the notice may not have been withdrawn"
            return .refused("the app machine `\(appMachine)` didn't answer within \(Int(timeout)) seconds, so \(maybe)")
        case .unreachable(let why):
            return .refused("couldn't reach the app machine `\(appMachine)` at \(origin), so \(notDone): \(why)")
        }
    }
}
