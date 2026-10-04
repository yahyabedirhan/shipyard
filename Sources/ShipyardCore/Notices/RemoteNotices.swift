import Foundation
import ShipyardNotices

/// Collecting the notices another machine's agents left with its
/// herdr-shipyard plugin (`PluginNoticeRoute`), on the same poll and
/// through the same Herdr connection as its pings (ADR 0005).
///
/// Two of the plugin's actions, each read from its command log as the ping
/// list is: `notices` lists what waits, oldest first, as
/// `{"version":1,"truncated":<bool>,"notices":[…]}` (within 48 KiB; the
/// rest wait for the next poll), and `notices-read` removes what that
/// listing handed out.
extension RemotePingReader {
    /// The plugin's action that lists the notices waiting on the machine.
    public static let noticesActionID = "notices"
    /// Its action that removes the ones the last listing handed out.
    public static let noticesReadActionID = "notices-read"

    /// The notices waiting on the machine `label`, oldest first, taken off
    /// it: listed, then removed there. None when they couldn't be listed or
    /// removed (the machine, Herdr or the plugin failing, or a plugin too
    /// old to hold notices), so a notice is shown at most once; ones left
    /// behind wait for the next poll, and the plugin drops them after an
    /// hour. A notice in the listing that doesn't read is taken and dropped.
    public func takeNotices(machine label: String) async -> [QueuedNotice] {
        let taken: Result<[QueuedNotice], Failure> = await timed(label) {
            guard case .success(let stdout) = await self.output(of: Self.noticesActionID, on: label),
                  let listing = NoticeListing.decode(stdout)
            else { return .failure(Failure("\(label)'s notices couldn't be listed")) }
            guard !listing.notices.isEmpty else { return .success([]) }
            guard case .success = await self.output(of: Self.noticesReadActionID, on: label) else {
                return .failure(Failure("\(label)'s notices couldn't be removed"))
            }
            return .success(listing.notices.compactMap(\.queued))
        }
        return (try? taken.get()) ?? []
    }
}

/// The plugin's `notices` listing.
struct NoticeListing: Decodable {
    /// The listing's contract version this build reads.
    static let currentVersion = 1

    var version: Int
    var notices: [Entry]

    /// One stored notice, `nil` when it doesn't read as a `QueuedNotice`.
    struct Entry: Decodable {
        var queued: QueuedNotice?

        init(from decoder: any Decoder) throws {
            queued = try? QueuedNotice(from: decoder)
        }
    }

    /// The listing `stdout` holds, or `nil` when it isn't one this build reads.
    static func decode(_ stdout: String) -> NoticeListing? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let listing = try? decoder.decode(NoticeListing.self, from: Data(stdout.utf8)),
              listing.version == currentVersion
        else { return nil }
        return listing
    }
}
