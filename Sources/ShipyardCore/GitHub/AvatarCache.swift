import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in account's avatar for the panel's header (#49), kept on
/// disk: downloaded once, and again only when the viewer's `avatarURL`
/// changes (GitHub changes its `v=` when the picture changes). The image
/// bytes are handed back as they came; the app draws them clipped to a circle.
///
/// It holds one avatar, the account's: `avatar` and the URL it came from,
/// `avatar-url`, in `directory`. A failed download (offline, a non-200, an
/// empty body) returns `nil` and stores nothing, so the header shows the
/// handle alone and the next ask tries again. The request carries no
/// token: avatars are public, served from `avatars.githubusercontent.com`.
public actor AvatarCache {
    /// The size asked for, in pixels (`s=`): the header's 20 pt at 3×.
    public static let pixelSize = 60

    private let directory: URL
    private let transport: any HTTPTransport
    /// What was last read or downloaded, so the panel opening again reads nothing.
    private var memory: (url: URL, data: Data)?
    /// The download under way, so asks made meanwhile share it.
    private var loading: (url: URL, task: Task<Data?, Never>)?

    public init(directory: URL, transport: any HTTPTransport) {
        self.directory = directory
        self.transport = transport
    }

    /// The URL downloaded for `avatarURL`: the same, asking for `pixelSize`.
    public static func downloadURL(for avatarURL: URL) -> URL {
        guard var components = URLComponents(url: avatarURL, resolvingAgainstBaseURL: false) else { return avatarURL }
        var items = (components.queryItems ?? []).filter { $0.name != "s" }
        items.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components.queryItems = items
        return components.url ?? avatarURL
    }

    /// The avatar at `url`: from memory, from disk when it was stored for
    /// the same URL, else downloaded and stored. `nil` when the download fails.
    public func image(for url: URL) async -> Data? {
        if let memory, memory.url == url { return memory.data }
        if let stored = stored(for: url) {
            memory = (url, stored)
            return stored
        }
        if let loading, loading.url == url { return await loading.task.value }
        let transport = transport
        let task = Task { await Self.download(url, transport: transport) }
        loading = (url, task)
        let data = await task.value
        // An ask for another URL since (the avatar changed meanwhile) wins
        // the disk and memory; this one only answers its caller.
        let superseded = loading.map { $0.url != url } ?? false
        if !superseded { loading = nil }
        guard let data else { return nil }
        guard !superseded else { return data }
        store(data, for: url)
        memory = (url, data)
        return data
    }

    private var imageFile: URL { directory.appendingPathComponent("avatar") }
    private var urlFile: URL { directory.appendingPathComponent("avatar-url") }

    private func stored(for url: URL) -> Data? {
        guard let storedURL = try? String(contentsOf: urlFile, encoding: .utf8),
              storedURL == url.absoluteString,
              let data = try? Data(contentsOf: imageFile), !data.isEmpty else { return nil }
        return data
    }

    /// Writes the image, then the URL it came from, so a crash between the
    /// two leaves a URL that doesn't match and the next ask downloads again.
    private func store(_ data: Data, for url: URL) {
        let manager = FileManager.default
        try? manager.removeItem(at: urlFile)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: imageFile, options: .atomic)
            try Data(url.absoluteString.utf8).write(to: urlFile, options: .atomic)
        } catch {
            // Not kept on disk: memory still has it, and the next launch downloads it again.
        }
    }

    private static func download(_ url: URL, transport: any HTTPTransport) async -> Data? {
        let request = URLRequest(url: downloadURL(for: url))
        guard let (data, response) = try? await transport.send(request),
              response.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }
}
