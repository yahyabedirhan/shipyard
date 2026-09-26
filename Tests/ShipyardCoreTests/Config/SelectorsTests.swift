import Foundation
@testable import ShipyardCore
import Testing

@Suite("Author selectors")
struct AuthorSelectorTests {
    /// The parsed selector, or the message it's rejected with.
    private func parse(_ text: String) -> Result<AuthorSelector, AuthorSelector.Rejection> {
        Result { () throws(AuthorSelector.Rejection) in try AuthorSelector(parsing: text) }
    }

    @Test("bare words are author groups and @ marks a login")
    func parsing() throws {
        #expect(try AuthorSelector(parsing: "me") == .me)
        #expect(try AuthorSelector(parsing: "others") == .others)
        #expect(try AuthorSelector(parsing: "bots") == .bots)
        #expect(try AuthorSelector(parsing: "@octocat") == .login("octocat"))
        #expect(try AuthorSelector(parsing: "@dependabot[bot]") == .login("dependabot[bot]"))
        #expect(try AuthorSelector(parsing: "@some-login-2") == .login("some-login-2"))
        // Each is written back the way it was read.
        for text in ["me", "others", "bots", "@octocat", "@dependabot[bot]"] {
            #expect(try AuthorSelector(parsing: text).description == text)
        }
    }

    @Test("a bare word that isn't a group is rejected with a suggestion")
    func unknownWords() {
        #expect(parse("bots2") == .failure(.init("unknown author `bots2` (did you mean `bots` or `@bots2`?)")))
        #expect(parse("bot") == .failure(.init("unknown author `bot` (did you mean `bots` or `@bot`?)")))
        #expect(parse("alice") == .failure(.init("unknown author `alice` (did you mean `@alice`?)")))
        // The old notification spelling for everyone.
        #expect(parse("any") == .failure(.init("unknown author `any` (an empty list means everyone)")))
        #expect(parse("two words") == .failure(.init("unknown author `two words` (expected `me`, `others`, `bots` or an `@login`)")))
    }

    @Test("a repository group or a repository is rejected as an author, with a hint")
    func repositories() {
        let takes = "`authors` takes `me`, `others`, `bots` or an `@login`"
        for group in ["owned", "organizations", "collaborator", "anywhere"] {
            #expect(parse(group) == .failure(.init("`\(group)` is a repository group; \(takes)")))
        }
        #expect(parse("octo/repo") == .failure(.init("`octo/repo` is a repository; \(takes)")))
        #expect(parse("octo/*") == .failure(.init("`octo/*` is a repository; \(takes)")))
    }

    @Test("an @ without a GitHub login after it is rejected")
    func badLogins() {
        #expect(parse("@") == .failure(.init("`@` isn't followed by a GitHub login")))
        #expect(parse("@two words") == .failure(.init("`@two words` isn't followed by a GitHub login")))
        #expect(parse("@octo/repo") == .failure(.init("`@octo/repo` isn't followed by a GitHub login")))
    }

    struct AuthorCase: Sendable, CustomTestStringConvertible {
        var author: String
        var kind: AuthorKind
        var matches: [AuthorSelector]
        var testDescription: String { author }
    }

    @Test("the groups cover every author once, and a login matches ignoring case", arguments: [
        AuthorCase(author: "yabepa", kind: .me, matches: [.me, .login("yabepa")]),
        // The viewer's login, where the item didn't say it's theirs.
        AuthorCase(author: "YaBePa", kind: .other, matches: [.me, .login("yabepa")]),
        AuthorCase(author: "octocat", kind: .other, matches: [.others]),
        AuthorCase(author: "dependabot[bot]", kind: .bot, matches: [.bots, .login("Dependabot[bot]")]),
        // A `[bot]` login counts as a bot even where the account type didn't say.
        AuthorCase(author: "renovate[bot]", kind: .other, matches: [.bots]),
    ])
    func matching(_ author: AuthorCase) {
        let candidates: [AuthorSelector] = [.me, .others, .bots, .login("yabepa"), .login("Dependabot[bot]")]
        let matched = candidates.filter { $0.matches(author: author.author, kind: author.kind, viewer: "yabepa") }
        #expect(matched == author.matches)
    }
}

@Suite("Author filters")
struct AuthorFilterTests {
    private func includes(_ filter: AuthorFilter, _ author: String, _ kind: AuthorKind = .other) -> Bool {
        filter.includes(author: author, kind: kind, viewer: "yabepa")
    }

    @Test("an empty filter lists everyone")
    func everyone() {
        let filter = AuthorFilter()
        #expect(includes(filter, "yabepa", .me))
        #expect(includes(filter, "octocat"))
        #expect(includes(filter, "dependabot[bot]", .bot))
    }

    @Test("hide leaves those authors out")
    func hide() {
        let filter = AuthorFilter(hide: [.me, .bots])
        #expect(!includes(filter, "yabepa", .me))
        #expect(!includes(filter, "dependabot[bot]", .bot))
        #expect(includes(filter, "octocat"))
    }

    @Test("show keeps only those authors")
    func show() {
        let filter = AuthorFilter(show: [.login("dependabot[bot]")])
        #expect(includes(filter, "dependabot[bot]", .bot))
        #expect(!includes(filter, "renovate[bot]", .bot))
        #expect(!includes(filter, "octocat"))
    }

    @Test("show minus hide: hide wins")
    func showMinusHide() {
        let filter = AuthorFilter(show: [.bots], hide: [.login("renovate[bot]")])
        #expect(includes(filter, "dependabot[bot]", .bot))
        #expect(!includes(filter, "renovate[bot]", .bot))
        #expect(!includes(filter, "octocat"))
    }
}
