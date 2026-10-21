import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in account's avatar for the panel's header, kept on
/// disk: downloaded once, and again when the viewer's `avatarURL` changes
/// or the kept one is a day old. GitHub sometimes keeps the URL (its `v=`)
/// when the picture changes, so the URL alone can keep an old picture
/// forever. The image bytes are handed back as they came; the app draws
/// them clipped to a circle.
///
/// It holds one avatar, the account's: `avatar` and the URL it came from,
/// `avatar-url`, in `directory`; the image file's modification date is
/// when it was downloaded. A failed download (offline, a non-200, an
/// empty body) stores nothing and returns the kept avatar while it is for
/// the same URL, else `nil`, so the header shows the handle alone; the
/// next ask tries again. The request carries no token: avatars are
/// public, served from `avatars.githubusercontent.com`. A file URL (a
/// demo run's made-up account, `DemoItems`) is read from disk instead.
public actor AvatarCache {
    /// The size asked for, in pixels (`s=`): the header's 20 pt at 3×.
    public static let pixelSize = 60
    /// How long a kept avatar is shown before it is downloaded again.
    public static let maxAge: TimeInterval = 24 * 60 * 60

    private let directory: URL
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private var memory: Kept?
    private var loading: (url: URL, task: Task<Data?, Never>)?

    private struct Kept {
        var url: URL
        var data: Data
        var downloaded: Date
    }

    public init(directory: URL, transport: any HTTPTransport, clock: any WallClock = SystemClock()) {
        self.directory = directory
        self.transport = transport
        self.clock = clock
    }

    /// The URL downloaded for `avatarURL`: the same, asking for `pixelSize`.
    public static func downloadURL(for avatarURL: URL) -> URL {
        guard !avatarURL.isFileURL else { return avatarURL }
        guard var components = URLComponents(url: avatarURL, resolvingAgainstBaseURL: false) else { return avatarURL }
        var items = (components.queryItems ?? []).filter { $0.name != "s" }
        items.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components.queryItems = items
        return components.url ?? avatarURL
    }

    /// The avatar at `url`: from memory, from disk when it was stored for
    /// the same URL less than `maxAge` ago, else downloaded and stored.
    /// When the download fails, the kept avatar for `url` however old,
    /// else `nil`.
    public func image(for url: URL) async -> Data? {
        if memory?.url != url { memory = stored(for: url) }
        if let memory, clock.now.timeIntervalSince(memory.downloaded) < Self.maxAge { return memory.data }
        let stale = memory?.data
        if let loading, loading.url == url { return await loading.task.value ?? stale }
        let transport = transport
        let task = Task { await Self.download(url, transport: transport) }
        loading = (url, task)
        let data = await task.value
        let superseded = loading.map { $0.url != url } ?? false
        if !superseded { loading = nil }
        guard let data else { return stale }
        guard !superseded else { return data }
        let now = clock.now
        store(data, for: url, at: now)
        memory = Kept(url: url, data: data, downloaded: now)
        return data
    }

    private var imageFile: URL { directory.appendingPathComponent("avatar") }
    private var urlFile: URL { directory.appendingPathComponent("avatar-url") }

    private func stored(for url: URL) -> Kept? {
        guard let storedURL = try? String(contentsOf: urlFile, encoding: .utf8),
              storedURL == url.absoluteString,
              let data = try? Data(contentsOf: imageFile), !data.isEmpty else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: imageFile.path)
        let downloaded = attributes?[.modificationDate] as? Date ?? .distantPast
        return Kept(url: url, data: data, downloaded: downloaded)
    }

    private func store(_ data: Data, for url: URL, at date: Date) {
        let manager = FileManager.default
        try? manager.removeItem(at: urlFile)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: imageFile, options: .atomic)
            try manager.setAttributes([.modificationDate: date], ofItemAtPath: imageFile.path)
            try Data(url.absoluteString.utf8).write(to: urlFile, options: .atomic)
        } catch {
        }
    }

    private static func download(_ url: URL, transport: any HTTPTransport) async -> Data? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return data
        }
        let request = URLRequest(url: downloadURL(for: url))
        guard let (data, response) = try? await transport.send(request),
              response.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }
}
