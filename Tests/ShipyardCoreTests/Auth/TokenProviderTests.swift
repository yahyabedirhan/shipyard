import Foundation
import ShipyardCore
import Testing

/// A token store that can't be read, like a locked Keychain.
private struct UnreadableTokenStore: TokenStore {
    struct Unreadable: Error {}
    func token() throws -> String? { throw Unreadable() }
    func save(_ token: String) throws { throw Unreadable() }
    func delete() throws { throw Unreadable() }
}

@Suite("Token provider")
struct TokenProviderTests {
    @Test("the token store comes first, and gh isn't asked")
    func tokenStoreFirst() {
        let gh = FakeGhLookup(token: "gho_fromgh")
        let provider = TokenProvider(store: InMemoryTokenStore(token: "gho_stored"), gh: gh)
        #expect(provider.current() == FoundToken(value: "gho_stored", source: .tokenStore))
        #expect(gh.lookups == 0)
    }

    @Test("gh's token is used when the token store is empty")
    func ghSecond() {
        let provider = TokenProvider(store: InMemoryTokenStore(), gh: FakeGhLookup(token: "gho_fromgh"))
        #expect(provider.current() == FoundToken(value: "gho_fromgh", source: .gh))
    }

    @Test("an empty stored token counts as none")
    func emptyStoredToken() {
        let provider = TokenProvider(store: InMemoryTokenStore(token: ""), gh: FakeGhLookup(token: "gho_fromgh"))
        #expect(provider.current()?.source == .gh)
    }

    @Test("a token store that can't be read falls back to gh")
    func unreadableStore() {
        let provider = TokenProvider(store: UnreadableTokenStore(), gh: FakeGhLookup(token: "gho_fromgh"))
        #expect(provider.current()?.source == .gh)
    }

    @Test("no token anywhere is none")
    func none() {
        let provider = TokenProvider(store: InMemoryTokenStore(), gh: FakeGhLookup())
        #expect(provider.current() == nil)
    }
}

@Suite("Finding gh")
struct GhCLITests {
    @Test("Apple Silicon's Homebrew path is tried first")
    func homebrewFirst() {
        let found = GhCLI.locate(
            isExecutable: { $0 == "/opt/homebrew/bin/gh" || $0 == "/usr/local/bin/gh" || $0 == "/bin/gh" },
            pathEnvironment: "/bin"
        )
        #expect(found == "/opt/homebrew/bin/gh")
    }

    @Test("Intel's Homebrew path comes before PATH")
    func intelSecond() {
        let found = GhCLI.locate(isExecutable: { $0 == "/usr/local/bin/gh" || $0 == "/bin/gh" }, pathEnvironment: "/bin")
        #expect(found == "/usr/local/bin/gh")
    }

    @Test("PATH is searched in order after the known paths")
    func pathLast() {
        let found = GhCLI.locate(
            isExecutable: { $0 == "/custom/bin/gh" || $0 == "/later/gh" },
            pathEnvironment: "/nope::/custom/bin/:/later"
        )
        #expect(found == "/custom/bin/gh")
    }

    @Test("no gh anywhere, or no PATH at all as in an .app, is nil")
    func notFound() {
        #expect(GhCLI.locate(isExecutable: { _ in false }, pathEnvironment: "/a:/b") == nil)
        #expect(GhCLI.locate(isExecutable: { _ in false }, pathEnvironment: nil) == nil)
    }

    @Test("runs `gh auth token` at the found path and trims the token")
    func runsAuthToken() {
        let calls = Locked<[[String]]>([])
        let gh = GhCLI(isExecutable: { $0 == "/usr/local/bin/gh" }, pathEnvironment: nil) { executable, arguments in
            calls.withValue { $0.append([executable] + arguments) }
            return CommandOutput(status: 0, standardOutput: "gho_fromgh\n")
        }
        #expect(gh.token() == "gho_fromgh")
        #expect(calls.current == [["/usr/local/bin/gh", "auth", "token"]])
    }

    @Test("gh signed out (non-zero exit), empty output or failing to start is no token")
    func noToken() {
        let signedOut = GhCLI(isExecutable: { _ in true }, pathEnvironment: nil) { _, _ in
            CommandOutput(status: 1, standardOutput: "")
        }
        let empty = GhCLI(isExecutable: { _ in true }, pathEnvironment: nil) { _, _ in
            CommandOutput(status: 0, standardOutput: " \n")
        }
        let unstartable = GhCLI(isExecutable: { _ in true }, pathEnvironment: nil) { _, _ in nil }
        #expect(signedOut.token() == nil)
        #expect(empty.token() == nil)
        #expect(unstartable.token() == nil)
    }

    @Test("gh isn't run when it isn't found")
    func notRunWhenMissing() {
        let ran = Locked(false)
        let gh = GhCLI(isExecutable: { _ in false }, pathEnvironment: "/bin") { _, _ in
            ran.withValue { $0 = true }
            return CommandOutput(status: 0, standardOutput: "gho_x")
        }
        #expect(gh.token() == nil)
        #expect(!ran.current)
    }
}
