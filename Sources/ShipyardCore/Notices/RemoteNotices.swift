import Foundation
import ShipyardNotices

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

struct NoticeListing: Decodable {
    static let currentVersion = 1

    var version: Int
    var notices: [Entry]

    struct Entry: Decodable {
        var queued: QueuedNotice?

        init(from decoder: any Decoder) throws {
            queued = try? QueuedNotice(from: decoder)
        }
    }

    static func decode(_ stdout: String) -> NoticeListing? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let listing = try? decoder.decode(NoticeListing.self, from: Data(stdout.utf8)),
              listing.version == currentVersion
        else { return nil }
        return listing
    }
}
