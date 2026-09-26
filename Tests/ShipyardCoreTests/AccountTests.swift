import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let userURL = Harness.userURL
private let avatarURL = URL(string: "https://avatars.githubusercontent.com/u/42?v=4")!
private let newAvatarURL = URL(string: "https://avatars.githubusercontent.com/u/42?v=5")!
/// A few bytes standing in for a PNG: the cache stores what it's given.
private let avatarBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
private let newAvatarBytes = Data([0x89, 0x50, 0x4E, 0x47, 4, 5, 6])

/// The header's account: who shipyard is signed in as, its profile
/// and its avatar.
@Suite("The connected account")
@MainActor
struct AccountTests {
    // MARK: - The viewer

    @Test("signing in keeps the account's name, avatar and profile from GET /user")
    func viewerFields() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, try .fixture("rest-user.json"))

        await harness.shipyard.start()

        let viewer = try #require(harness.shipyard.viewer)
        #expect(viewer.login == "yabepa")
        #expect(viewer.id == 42)
        #expect(viewer.name == "Yahya Bedirhan Pak")
        #expect(viewer.avatarURL == avatarURL)
        #expect(viewer.profileURL == URL(string: "https://github.com/yabepa")!)
    }

    @Test("an answer without a name, avatar or profile link still signs in; the profile is github.com/<login>")
    func viewerWithoutOptionalFields() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, .json(#"{"login":"yabepa","id":42,"name":null}"#))

        await harness.shipyard.start()

        let viewer = try #require(harness.shipyard.viewer)
        #expect(viewer.name == nil)
        #expect(viewer.avatarURL == nil)
        #expect(viewer.profileURL == URL(string: "https://github.com/yabepa")!)
    }

    // MARK: - Opening the profile

    @Test("the header's account opens the profile on GitHub")
    func openProfile() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, try .fixture("rest-user.json"))
        await harness.shipyard.start()

        harness.shipyard.openProfile()

        #expect(harness.opener.opened == [URL(string: "https://github.com/yabepa")!])
    }

    @Test("without a known account, opening the profile opens nothing")
    func openProfileUnknown() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(userURL, .failure())
        await harness.shipyard.start()

        harness.shipyard.openProfile()

        #expect(harness.shipyard.viewer == nil)
        #expect(harness.opener.opened.isEmpty)
    }

    // MARK: - The avatar

    @Test("the avatar is downloaded once, without the token, at the header's size")
    func avatarDownloadedOnce() async throws {
        let stub = StubHTTP()
        stub.on(AvatarCache.downloadURL(for: avatarURL), avatarBytesAnswer(avatarBytes))
        let cache = AvatarCache(directory: try temporaryDirectory(), transport: stub)

        let first = await cache.image(for: avatarURL)
        let second = await cache.image(for: avatarURL)

        #expect(first == avatarBytes)
        #expect(second == avatarBytes)
        #expect(stub.requests.count == 1)
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "v", value: "4")))
        #expect(query.contains(URLQueryItem(name: "s", value: String(AvatarCache.pixelSize))))
    }

    @Test("the avatar is kept on disk: the next launch reads it without downloading")
    func avatarKeptOnDisk() async throws {
        let directory = try temporaryDirectory()
        let stub = StubHTTP()
        stub.on(AvatarCache.downloadURL(for: avatarURL), avatarBytesAnswer(avatarBytes))
        _ = await AvatarCache(directory: directory, transport: stub).image(for: avatarURL)

        let relaunched = StubHTTP()
        let image = await AvatarCache(directory: directory, transport: relaunched).image(for: avatarURL)

        #expect(image == avatarBytes)
        #expect(relaunched.requests.isEmpty)
    }

    @Test("a new avatar URL downloads the avatar again, and replaces the one on disk")
    func avatarURLChanged() async throws {
        let directory = try temporaryDirectory()
        let stub = StubHTTP()
        stub.on(AvatarCache.downloadURL(for: avatarURL), avatarBytesAnswer(avatarBytes))
        stub.on(AvatarCache.downloadURL(for: newAvatarURL), avatarBytesAnswer(newAvatarBytes))
        let cache = AvatarCache(directory: directory, transport: stub)
        _ = await cache.image(for: avatarURL)

        let changed = await cache.image(for: newAvatarURL)
        let relaunched = await AvatarCache(directory: directory, transport: StubHTTP()).image(for: newAvatarURL)

        #expect(changed == newAvatarBytes)
        #expect(relaunched == newAvatarBytes)
        #expect(stub.requests.count == 2)
    }

    @Test("a failed download leaves no avatar, and the next ask tries again", arguments: [
        StubHTTP.Answer.failure(),
        .status(404),
        .status(200),
    ])
    func avatarDownloadFails(answer: StubHTTP.Answer) async throws {
        let stub = StubHTTP()
        stub.on(AvatarCache.downloadURL(for: avatarURL), answer, avatarBytesAnswer(avatarBytes))
        let cache = AvatarCache(directory: try temporaryDirectory(), transport: stub)

        let failed = await cache.image(for: avatarURL)
        let retried = await cache.image(for: avatarURL)

        #expect(failed == nil)
        #expect(retried == avatarBytes)
    }

    private func avatarBytesAnswer(_ bytes: Data) -> StubHTTP.Answer {
        StubHTTP.Answer(status: 200, headers: ["Content-Type": "image/png"], body: bytes)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-avatar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
