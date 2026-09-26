import Foundation
import ShipyardCore

/// A `URLOpening` that records the URLs it was asked to open.
final class RecordingURLOpener: URLOpening {
    private let log = Locked<[URL]>([])

    var opened: [URL] { log.current }

    func open(_ url: URL) { log.withValue { $0.append(url) } }
}
