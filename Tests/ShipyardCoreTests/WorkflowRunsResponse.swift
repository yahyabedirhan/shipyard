import Foundation
@testable import ShipyardCore

struct WorkflowRunsResponse {
    struct Run {
        var number: Int
        var name = "CI"
        var branch = "main"
        var event = "push"
        var status = "completed"
        var conclusion: String? = "success"
        var createdAt = "2026-09-25T11:00:00Z"
        var updatedAt = "2026-09-25T11:10:00Z"
        var actor = "yabepa"
        var actorType = "User"

        init(_ number: Int) { self.number = number }

        func url(in repository: String) -> URL {
            URL(string: "https://github.com/\(repository)/actions/runs/\(9000 + number)")!
        }

        func json(in repository: String) -> [String: Any] {
            [
                "id": 9000 + number,
                "name": name,
                "node_id": "WFR_kwLO\(9000 + number)",
                "head_branch": branch,
                "head_sha": String(repeating: "a", count: 40),
                "display_title": "A change",
                "run_number": number,
                "run_attempt": 1,
                "event": event,
                "status": status,
                "conclusion": conclusion.map { $0 as Any } ?? NSNull(),
                "html_url": url(in: repository).absoluteString,
                "url": "https://api.github.com/repos/\(repository)/actions/runs/\(9000 + number)",
                "pull_requests": [Any](),
                "created_at": createdAt,
                "updated_at": updatedAt,
                "run_started_at": createdAt,
                "actor": ["login": actor, "id": 42, "type": actorType, "site_admin": false],
                "triggering_actor": ["login": actor, "id": 42, "type": actorType, "site_admin": false],
            ]
        }
    }

    var repository: String
    var runs: [Run]

    init(_ repository: String, _ runs: [Run]) {
        self.repository = repository
        self.runs = runs
    }

    static func url(_ repository: String) -> URL {
        GitHubClient.apiURL.appendingPathComponent("repos/\(repository)/actions/runs")
    }

    func answer(etag: String? = nil, remaining: Int = 4900) -> StubHTTP.Answer {
        var headers = Harness.rateLimitHeaders(remaining: remaining, resource: "core")
        headers["ETag"] = etag
        var answer = StubHTTP.Answer.json("", headers: headers)
        answer.body = try! JSONSerialization.data(withJSONObject: [
            "total_count": runs.count,
            "workflow_runs": runs.map { $0.json(in: repository) },
        ])
        return answer
    }

    static func notModified(etag: String, remaining: Int = 4900) -> StubHTTP.Answer {
        var headers = Harness.rateLimitHeaders(remaining: remaining, resource: "core")
        headers["ETag"] = etag
        return .status(304, headers: headers)
    }
}
