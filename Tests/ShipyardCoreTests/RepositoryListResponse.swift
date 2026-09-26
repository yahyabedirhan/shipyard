import Foundation
@testable import ShipyardCore

/// GraphQL answers to the repository resolver's lookups, built in the test:
/// a repository group's (`viewer.repositories`) or an owner's
/// (`repositoryOwner(login).repositories`), one page each.
struct RepositoryListResponse {
    /// One repository as the listing describes it.
    struct Repository {
        var slug: String
        var isArchived = false
        var isFork = false

        init(_ slug: String, archived: Bool = false, fork: Bool = false) {
            self.slug = slug
            isArchived = archived
            isFork = fork
        }
    }

    /// The body marker of a group's lookup, for `StubHTTP.on(_:_:body:answers:)`.
    static let groupQuery = "ShipyardGroupRepositories"
    /// The body marker of an owner's lookup.
    static let ownerQuery = "ShipyardOwnerRepositories"

    /// One page of `repositories`; `next` is the cursor of the page after,
    /// when there is one.
    static func page(_ repositories: [Repository], next: String? = nil, owner: Bool = false) -> StubHTTP.Answer {
        let connection: [String: Any] = [
            "pageInfo": ["hasNextPage": next != nil, "endCursor": next.map { $0 as Any } ?? NSNull()],
            "nodes": repositories.map { repository in
                [
                    "nameWithOwner": repository.slug,
                    "isPrivate": false,
                    "isArchived": repository.isArchived,
                    "isFork": repository.isFork,
                    "pushedAt": "2026-09-24T10:00:00Z",
                ] as [String: Any]
            },
        ]
        return answer(["\(owner ? "repositoryOwner" : "viewer")": ["repositories": connection]])
    }

    /// The answer for an owner GitHub doesn't know, or hides from the token.
    static var missingOwner: StubHTTP.Answer { answer(["repositoryOwner": NSNull()]) }

    private static func answer(_ data: [String: Any]) -> StubHTTP.Answer {
        var data = data
        data["rateLimit"] = ["limit": 5000, "remaining": 4990, "used": 10, "resetAt": "2026-09-25T12:42:00Z", "cost": 1]
        var answer = StubHTTP.Answer.json("", headers: Harness.rateLimitHeaders(remaining: 4990))
        answer.body = try! JSONSerialization.data(withJSONObject: ["data": data])
        return answer
    }
}
