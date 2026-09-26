import Foundation

/// A GraphQL answer for one repository, built in the test, for scenarios
/// that change a pull request or an issue between refreshes (a push, a
/// review request, failed checks, a merge, a comment). It has the recorded
/// fixtures' shape.
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
        /// The branch it would merge; `change-<number>` unless set.
        var headRefName: String?

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
                "headRefName": headRefName ?? "change-\(number)",
                "author": ["login": author, "__typename": authorType],
                "comments": ["totalCount": comments],
                "reviews": ["totalCount": reviews],
                "reviewRequests": ["nodes": reviewRequests.map { ["requestedReviewer": ["__typename": "User", "login": $0]] }],
                "commits": ["nodes": [["commit": ["statusCheckRollup": checks.map { ["state": $0] as Any } ?? NSNull()]]]],
            ]
        }
    }

    /// One issue as GitHub would describe it.
    struct Issue {
        var number: Int
        var title = "A problem"
        /// `OPEN` or `CLOSED`.
        var state = "OPEN"
        var author = "octocat"
        var authorType = "User"
        var createdAt = "2026-09-25T09:00:00Z"
        var updatedAt = "2026-09-25T10:00:00Z"
        var closedAt: String?
        var comments = 0

        init(_ number: Int) { self.number = number }

        func url(in repository: String) -> URL {
            URL(string: "https://github.com/\(repository)/issues/\(number)")!
        }

        func json(in repository: String) -> [String: Any] {
            [
                "number": number,
                "title": title,
                "url": url(in: repository).absoluteString,
                "state": state,
                "createdAt": createdAt,
                "updatedAt": updatedAt,
                "closedAt": closedAt.map { $0 as Any } ?? NSNull(),
                "author": ["login": author, "__typename": authorType],
                "comments": ["totalCount": comments],
            ]
        }
    }

    var repository: String
    var pullRequests: [PullRequest]
    /// The repository's issues; `nil` answers as GitHub does when the query
    /// didn't ask for them (no `openIssues`/`closedIssues` keys).
    var issues: [Issue]?
    var viewer = "yabepa"
    /// The repository's default branch, answered as `defaultBranchRef`.
    var defaultBranch = "main"
    /// Answer as GitHub does when the query asked only for open pull
    /// requests' heads (runs shown, pull requests not): `openPullRequestHeads`.
    var headsOnly = false
    /// Answer as GitHub does for a repository that's gone or out of reach:
    /// a `null` alias and a `NOT_FOUND` error.
    var missing = false

    init(_ repository: String, _ pullRequests: [PullRequest], issues: [Issue]? = nil, missing: Bool = false) {
        self.repository = repository
        self.pullRequests = pullRequests
        self.issues = issues
        self.missing = missing
    }

    /// The answer, with GitHub's rate-limit headers.
    var answer: StubHTTP.Answer { Self.answer([self]) }

    /// One answer for several repositories, as `repo0`, `repo1`… in the
    /// order the query asks for them: the configuration's, each repository
    /// once. A request carries one batch of repositories, so a refresh with
    /// more than a batch needs one answer per batch. The body reports `cost`,
    /// and the body and headers `remaining`.
    static func answer(_ responses: [PullRequestsResponse], cost: Int = 1, remaining: Int = 4990) -> StubHTTP.Answer {
        var data: [String: Any] = [
            "viewer": ["login": responses.first?.viewer ?? "yabepa"],
            "rateLimit": [
                "limit": 5000, "remaining": remaining, "used": 5000 - remaining,
                "resetAt": "2026-09-25T12:42:00Z", "cost": cost,
            ],
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
            var node: [String: Any] = [
                "nameWithOwner": response.repository,
                "defaultBranchRef": ["name": response.defaultBranch],
            ]
            if response.headsOnly {
                node["openPullRequestHeads"] = ["nodes": response.pullRequests.filter { $0.state == "OPEN" }.map {
                    ["headRefName": $0.headRefName ?? "change-\($0.number)"]
                }]
            } else {
                node["openPullRequests"] = ["nodes": open]
                node["closedPullRequests"] = ["nodes": closed]
            }
            if let issues = response.issues {
                node["openIssues"] = ["nodes": issues.filter { $0.state == "OPEN" }.map { $0.json(in: response.repository) }]
                node["closedIssues"] = ["nodes": issues.filter { $0.state != "OPEN" }.map { $0.json(in: response.repository) }]
            }
            data[alias] = node
        }
        var body: [String: Any] = ["data": data]
        if !errors.isEmpty { body["errors"] = errors }
        var answer = StubHTTP.Answer.json("", headers: Harness.rateLimitHeaders(remaining: remaining))
        answer.body = try! JSONSerialization.data(withJSONObject: body)
        return answer
    }
}
