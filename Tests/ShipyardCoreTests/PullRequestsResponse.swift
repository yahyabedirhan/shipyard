import Foundation

struct PullRequestsResponse {
    struct PullRequest {
        var number: Int
        var title = "A change"
        var state = "OPEN"
        var isDraft = false
        var author = "yabepa"
        var authorType = "User"
        var createdAt = "2026-09-25T09:00:00Z"
        var updatedAt = "2026-09-25T10:00:00Z"
        var closedAt: String?
        var comments = 0
        var reviews = 0
        var reviewRequests: [String] = []
        var teamReviewRequests: [String] = []
        var checks: String? = "PENDING"
        var headRefName: String?

        init(_ number: Int) { self.number = number }

        func url(in repository: String) -> URL {
            URL(string: "https://github.com/\(repository)/pull/\(number)")!
        }

        func waitsOn(_ viewer: String) -> Bool {
            state == "OPEN" && (reviewRequests.contains { $0.lowercased() == viewer.lowercased() } || !teamReviewRequests.isEmpty)
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
                "commits": ["nodes": [["commit": ["statusCheckRollup": checks.map { ["state": $0] as Any } ?? NSNull()]]]],
            ]
        }
    }

    struct Issue {
        var number: Int
        var title = "A problem"
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
    var issues: [Issue]?
    var viewer = "yabepa"
    var defaultBranch = "main"
    var headsOnly = false
    var missing = false

    init(_ repository: String, _ pullRequests: [PullRequest], issues: [Issue]? = nil, missing: Bool = false) {
        self.repository = repository
        self.pullRequests = pullRequests
        self.issues = issues
        self.missing = missing
    }

    var answer: StubHTTP.Answer { Self.answer([self]) }

    enum ReviewSearch {
        case waiting
        case pullRequests([(repository: String, pullRequest: PullRequest)], total: Int? = nil)
        case failed(String)
    }

    static func answer(
        _ responses: [PullRequestsResponse],
        cost: Int = 1,
        remaining: Int = 4990,
        reviewSearch: ReviewSearch = .waiting
    ) -> StubHTTP.Answer {
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
        let viewer = responses.first?.viewer ?? "yabepa"
        switch reviewSearch {
        case .failed(let message):
            data["reviewSearch"] = NSNull()
            errors.append(["path": ["reviewSearch"], "message": message])
        case .waiting, .pullRequests:
            let waiting: [(repository: String, pullRequest: PullRequest)]
            var total: Int?
            if case .pullRequests(let pullRequests, let matched) = reviewSearch {
                waiting = pullRequests
                total = matched
            } else {
                waiting = responses.filter { !$0.missing && !$0.headsOnly }.flatMap { response in
                    response.pullRequests.filter { $0.waitsOn(viewer) }.map { (response.repository, $0) }
                }
            }
            data["reviewSearch"] = [
                "issueCount": total ?? waiting.count,
                "nodes": waiting.map { repository, pullRequest in
                    var node = pullRequest.json(in: repository)
                    node["repository"] = ["nameWithOwner": repository]
                    return node
                },
            ] as [String: Any]
        }
        var body: [String: Any] = ["data": data]
        if !errors.isEmpty { body["errors"] = errors }
        var answer = StubHTTP.Answer.json("", headers: Harness.rateLimitHeaders(remaining: remaining))
        answer.body = try! JSONSerialization.data(withJSONObject: body)
        return answer
    }
}
