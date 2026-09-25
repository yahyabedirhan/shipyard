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

    init(_ repository: String, _ pullRequests: [PullRequest]) {
        self.repository = repository
        self.pullRequests = pullRequests
    }

    /// The answer, with GitHub's rate-limit headers.
    var answer: StubHTTP.Answer {
        let open = pullRequests.filter { $0.state == "OPEN" }.map { $0.json(in: repository) }
        let closed = pullRequests.filter { $0.state != "OPEN" }.map { $0.json(in: repository) }
        let body: [String: Any] = [
            "data": [
                "viewer": ["login": viewer],
                "repo0": [
                    "nameWithOwner": repository,
                    "openPullRequests": ["nodes": open],
                    "closedPullRequests": ["nodes": closed],
                ],
                "rateLimit": ["limit": 5000, "remaining": 4990, "used": 10, "resetAt": "2026-09-25T12:42:00Z", "cost": 1],
            ],
        ]
        var answer = StubHTTP.Answer.json("", headers: Harness.rateLimitHeaders(remaining: 4990))
        answer.body = try! JSONSerialization.data(withJSONObject: body)
        return answer
    }
}
