import Foundation

/// A GraphQL answer for one repository, built in the test, for scenarios
/// that change a pull request between refreshes (a push, a review request,
/// failed checks, a merge). It has the recorded fixtures' shape.
struct PullRequestsResponse {
    /// One pull request as GitHub would describe it.
    struct PullRequest {
        var number: Int
        var title = "A change"
        /// `OPEN`, `MERGED` or `CLOSED`.
        var state = "OPEN"
        var isDraft = false
        var author = "yabepa"
        var authorType = "User"
        var createdAt = "2026-09-25T09:00:00Z"
        var updatedAt = "2026-09-25T10:00:00Z"
        var closedAt: String?
        var comments = 0
        var reviews = 0
        /// Logins whose review is requested.
        var reviewRequests: [String] = []
        /// `statusCheckRollup.state`: `SUCCESS`, `FAILURE`, `PENDING`…; `nil` for none.
        var checks: String? = "PENDING"

        init(_ number: Int) { self.number = number }

        func url(in repository: String) -> URL {
            URL(string: "https://github.com/\(repository)/pull/\(number)")!
        }

        func json(in repository: String) -> [String: Any] {
            [
                "number": number,
                "title": title,
                "url": url(in: repository).absoluteString,
                "isDraft": isDraft,
                "state": state,
                "createdAt": createdAt,
                "updatedAt": updatedAt,
                "closedAt": closedAt.map { $0 as Any } ?? NSNull(),
                "mergedAt": state == "MERGED" ? (closedAt ?? updatedAt) as Any : NSNull(),
                "author": ["login": author, "__typename": authorType],
                "comments": ["totalCount": comments],
                "reviews": ["totalCount": reviews],
                "reviewRequests": ["nodes": reviewRequests.map { ["requestedReviewer": ["__typename": "User", "login": $0]] }],
                "commits": ["nodes": [["commit": ["statusCheckRollup": checks.map { ["state": $0] as Any } ?? NSNull()]]]],
            ]
        }
    }

    var repository: String
    var pullRequests: [PullRequest]
    var viewer = "yabepa"
    /// Answer as GitHub does for a repository that's gone or out of reach:
    /// a `null` alias and a `NOT_FOUND` error.
    var missing = false

    init(_ repository: String, _ pullRequests: [PullRequest], missing: Bool = false) {
        self.repository = repository
        self.pullRequests = pullRequests
        self.missing = missing
    }

    /// The answer, with GitHub's rate-limit headers.
    var answer: StubHTTP.Answer { Self.answer([self]) }

    /// One answer for several repositories, as `repo0`, `repo1`… in the
    /// order the query asks for them: the configuration's, each repository once.
    static func answer(_ responses: [PullRequestsResponse]) -> StubHTTP.Answer {
        var data: [String: Any] = [
            "viewer": ["login": responses.first?.viewer ?? "yabepa"],
            "rateLimit": ["limit": 5000, "remaining": 4990, "used": 10, "resetAt": "2026-09-25T12:42:00Z", "cost": 1],
        ]
        var errors: [[String: Any]] = []
        for (index, response) in responses.enumerated() {
            let alias = "repo\(index)"
            if response.missing {
                data[alias] = NSNull()
                errors.append([
                    "type": "NOT_FOUND",
                    "path": [alias],
                    "message": "Could not resolve to a Repository with the name '\(response.repository)'.",
                ])
                continue
            }
            let open = response.pullRequests.filter { $0.state == "OPEN" }.map { $0.json(in: response.repository) }
            let closed = response.pullRequests.filter { $0.state != "OPEN" }.map { $0.json(in: response.repository) }
            data[alias] = [
                "nameWithOwner": response.repository,
                "openPullRequests": ["nodes": open],
                "closedPullRequests": ["nodes": closed],
            ]
        }
        var body: [String: Any] = ["data": data]
        if !errors.isEmpty { body["errors"] = errors }
        var answer = StubHTTP.Answer.json("", headers: Harness.rateLimitHeaders(remaining: 4990))
        answer.body = try! JSONSerialization.data(withJSONObject: body)
        return answer
    }
}
