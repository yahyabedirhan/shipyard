import Foundation

/// What a notice request from another machine travels as, over the user's
/// tailnet (ADR 0010): one `POST /notify` whose body is the request's JSON
/// (`NoticeRequest`: the notice's own JSON, or `{"withdraw":"<id>"}`, as
/// every route carries it), answered with the app's verdict as JSON
/// (`NoticeVerdict.encoded()`). `tailscale serve` on the Mac adds the
/// sender's login as `Tailscale-User-Login` on its way to the app.
public enum TailnetWire {
    /// The path a request is posted to.
    public static let path = "/notify"
    /// The header `tailscale serve` fills with the login of the user whose
    /// device sent the request, and strips from what the device sent.
    public static let loginHeader = "Tailscale-User-Login"
    /// How long the command waits for the app's verdict on a small
    /// request: the app answers at once, and a Mac asleep or away shouldn't
    /// hold an agent up.
    public static let timeout: TimeInterval = 3
    /// The most a request's body may hold: a notice with the largest image
    /// (`Notice.largestImage`), base64 in its JSON, and room to spare.
    public static let largestBody = 8 << 20
    /// Why a notice whose click or a button focuses Herdr doesn't go over
    /// the tailnet: the request names no machine, so the Mac would focus
    /// its own Herdr, not the sender's. The command refuses it before
    /// sending, and the app refuses one that arrives anyway.
    public static let herdrRefusal = "a notice sent over the tailnet can't focus Herdr (--herdr or a herdr button): "
        + "the Mac would focus its own Herdr, not this machine's; use --open or --app, "
        + "or leave app-machine out of cli.toml to send it through the Mac's poll"

    /// How long to wait for the verdict on a body of `bytes`: `timeout`,
    /// and a second more for each started megabyte past the first, so a
    /// notice carrying an image has time to cross a slow link.
    public static func timeout(forBodyOf bytes: Int) -> TimeInterval {
        timeout + TimeInterval(max(0, (bytes - 1) >> 20))
    }
}

extension NoticeVerdict {
    /// The verdict as the app answers it: `{"shown":true}`, or
    /// `{"refused":"<why>"}`.
    public func encoded() -> Data {
        let wire: Wire
        switch self {
        case .shown: wire = Wire(shown: true)
        // The app never queues a notice; written for completeness.
        case .queued: wire = Wire(queued: true)
        case .refused(let why): wire = Wire(refused: why)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Two optionals and a string: nothing that can fail to encode.
        return (try? encoder.encode(wire)) ?? Data()
    }

    /// The verdict in `data`, or `nil` when it holds none: not the app's
    /// answer, such as a proxy's error page.
    public init?(answer data: Data) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        if wire.shown == true {
            self = .shown
        } else if wire.queued == true {
            self = .queued
        } else if let why = wire.refused {
            self = .refused(why)
        } else {
            return nil
        }
    }

    private struct Wire: Codable {
        var shown: Bool?
        var queued: Bool?
        var refused: String?
    }
}
