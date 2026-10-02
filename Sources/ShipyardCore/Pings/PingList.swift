import Foundation

/// The list of a machine's pings that `shipyard ping list --json` prints and
/// the Mac's shipyard reads from that machine through Herdr: part of the
/// CLI's public contract (ADR 0004).
///
/// ```json
/// {"pings":[…],"shipyardVersion":"0.0.6","truncated":false,"version":1}
/// ```
///
/// `version` is the contract's major version. A change a reader can ignore
/// (a new field) keeps it; one it can't bumps it, and a reader refuses any
/// version but its own. Each ping carries the fields a ping is sent with
/// (id, instance, title, body, sender, repository, projects, action, sent);
/// what a Mac records on it (seen, a failure) stays on that Mac.
public struct PingList: Equatable, Sendable {
    /// The contract version this build writes and reads.
    public static let currentVersion = 1
    /// At most this many pings are listed.
    public static let maxPings = 100
    /// The encoded document stays within this many bytes, well under the
    /// 64 KiB Herdr keeps of an action's output.
    public static let byteBudget = 48 * 1024

    /// The contract's major version.
    public var version: Int
    /// The shipyard version that produced the list (`ShipyardVersion.current`).
    public var shipyardVersion: String
    /// Newest first.
    public var pings: [Ping]
    /// Whether the list stopped early, at `maxPings` or `byteBudget`, so
    /// the machine holds pings it leaves out.
    public var truncated: Bool

    public init(
        version: Int = PingList.currentVersion,
        shipyardVersion: String = ShipyardVersion.current,
        pings: [Ping],
        truncated: Bool = false
    ) {
        self.version = version
        self.shipyardVersion = shipyardVersion
        self.pings = pings
        self.truncated = truncated
    }

    /// Why a list doesn't read.
    public enum DecodeError: Error, Equatable, Sendable {
        /// The list is another contract version, from the shipyard version
        /// named (when it says): shipyard on that machine (or on the Mac, for
        /// a newer one) needs updating.
        case unsupportedVersion(Int, shipyardVersion: String?)
        /// Not a ping list: not JSON, or a field missing or of the wrong type.
        case unreadable(String)

        /// What to tell the user about `machine` (its Herdr label).
        public func message(machine: String) -> String {
            switch self {
            case .unsupportedVersion(let version, let shipyardVersion):
                let from = shipyardVersion.map { " from shipyard \($0)" } ?? ""
                return "\(machine) lists pings in version \(version)\(from), and this shipyard reads version \(PingList.currentVersion): update shipyard on \(machine)"
            case .unreadable(let reason):
                return "\(machine)'s ping list doesn't read: \(reason)"
            }
        }
    }

    /// The JSON document for `pings`: newest first (by `sent`, then id), at
    /// most `maxPings` and within `byteBudget` bytes, stopping at the first
    /// ping that doesn't fit and setting `truncated` when it stops early.
    /// Each ping's `seen` and `failure` are left out. One line, no newline.
    public static func encode(_ pings: [Ping], shipyardVersion: String = ShipyardVersion.current) -> String {
        let sorted = pings
            .sorted { ($0.sent, $0.id) > ($1.sent, $1.id) }
            .map { ping -> Ping in
                var ping = ping
                ping.seen = nil
                ping.failure = nil
                return ping
            }
        // What the envelope costs with no pings (`false`, the longer of the
        // two), plus each ping and a comma: the document's size or a byte
        // over it, since the encoding is compact.
        let envelope = document(PingList(shipyardVersion: shipyardVersion, pings: [], truncated: false)).utf8.count
        var size = envelope
        var count = 0
        for ping in sorted.prefix(maxPings) {
            let cost = encoded(ping).count + (count == 0 ? 0 : 1)
            guard size + cost <= byteBudget else { break }
            size += cost
            count += 1
        }
        var list = PingList(shipyardVersion: shipyardVersion, pings: Array(sorted.prefix(count)), truncated: count < sorted.count)
        var text = document(list)
        // A safeguard: the size above is never short, but the document must never
        // exceed the budget, whatever the encoder does.
        while text.utf8.count > byteBudget, !list.pings.isEmpty {
            list.pings.removeLast()
            list.truncated = true
            text = document(list)
        }
        return text
    }

    /// Reads a list `encode` (of this or another build) made. Fields it
    /// doesn't know are ignored, and so is a ping's action of a kind it
    /// doesn't know (the ping reads without one).
    public static func decode(_ text: String) throws(DecodeError) -> PingList {
        try decode(Data(text.utf8))
    }

    /// Reads a list from its bytes, as `decode(_: String)`.
    public static func decode(_ data: Data) throws(DecodeError) -> PingList {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // The version first: another version's shape may not read at all.
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw .unreadable(reason(error))
        }
        guard header.version == currentVersion else {
            throw .unsupportedVersion(header.version, shipyardVersion: header.shipyardVersion)
        }
        do {
            let body = try decoder.decode(Body.self, from: data)
            return PingList(
                version: header.version,
                shipyardVersion: body.shipyardVersion,
                pings: body.pings.map(\.ping),
                truncated: body.truncated
            )
        } catch {
            throw .unreadable(reason(error))
        }
    }

    // MARK: - Encoding

    private enum CodingKeys: String, CodingKey {
        case version, shipyardVersion, pings, truncated
    }

    private struct Header: Decodable {
        var version: Int
        var shipyardVersion: String?
    }

    private struct Body: Decodable {
        var shipyardVersion: String
        var pings: [ListedPing]
        var truncated: Bool
    }

    /// A listed ping, read with only the fields it's sent with, and an
    /// action of an unknown kind read as none.
    private struct ListedPing: Decodable {
        var ping: Ping

        private enum CodingKeys: String, CodingKey {
            case id, instance, title, body, sender, repository, projects, action, sent
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ping = Ping(
                id: try container.decode(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title),
                projects: try container.decodeIfPresent([String].self, forKey: .projects) ?? [],
                sent: try container.decode(Date.self, forKey: .sent),
                repository: try container.decodeIfPresent(String.self, forKey: .repository),
                body: try container.decodeIfPresent(String.self, forKey: .body),
                sender: try container.decodeIfPresent(String.self, forKey: .sender),
                action: try? container.decodeIfPresent(PingAction.self, forKey: .action),
                instance: try container.decodeIfPresent(String.self, forKey: .instance)
            )
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private struct Envelope: Encodable {
        var list: PingList

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(list.version, forKey: .version)
            try container.encode(list.shipyardVersion, forKey: .shipyardVersion)
            try container.encode(list.pings, forKey: .pings)
            try container.encode(list.truncated, forKey: .truncated)
        }
    }

    /// Strings, dates and URLs always encode, so neither of these fails.
    private static func document(_ list: PingList) -> String {
        String(decoding: try! encoder.encode(Envelope(list: list)), as: UTF8.self)
    }

    private static func encoded(_ ping: Ping) -> Data {
        try! encoder.encode(ping)
    }

    private static func reason(_ error: any Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _):
            "\(key.stringValue) is missing"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "\(context.codingPath.map(\.stringValue).joined(separator: ".")) isn't what it should be"
        default:
            "it isn't JSON"
        }
    }
}
