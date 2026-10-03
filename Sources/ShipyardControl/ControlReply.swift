import Foundation

/// The app's answer to one request: `ok` with what to print on standard
/// output (`output`) and, rarely, a note for standard error (`error`), or a
/// refusal (`ok` false) whose `error` says why.
public struct ControlReply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var output: String
    public var error: String

    public init(ok: Bool, output: String = "", error: String = "") {
        self.ok = ok
        self.output = output
        self.error = error
    }

    /// Done: `output` printed as it is.
    public static func done(_ output: String, note: String = "") -> ControlReply {
        ControlReply(ok: true, output: output, error: note)
    }

    /// Refused: one line on standard error, exit 1.
    public static func refused(_ why: String) -> ControlReply {
        ControlReply(ok: false, error: why)
    }

    /// The reply as one JSON object.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try! encoder.encode(self)
    }

    /// Reads the app's reply.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlReply {
        do {
            return try JSONDecoder().decode(ControlReply.self, from: data)
        } catch {
            throw .unreadable("the app's reply doesn't read")
        }
    }
}
