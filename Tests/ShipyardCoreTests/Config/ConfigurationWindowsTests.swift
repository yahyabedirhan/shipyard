import Foundation
@testable import ShipyardConfig
@testable import ShipyardCore
import Testing

@Suite("Configuration: closed and finished windows")
struct ConfigurationWindowsTests {
    @Test("a window is a whole number and one unit: seconds, minutes, hours or days")
    func units() throws {
        let cases: [(String, TimeInterval)] = [
            ("45s", 45), ("30m", 1800), ("12h", 43_200), ("7d", 604_800), ("0", 0), ("0s", 0), ("0m", 0), ("90m", 5400),
        ]
        for (text, seconds) in cases {
            #expect(try ConfigurationDuration.parse(text) == seconds, "\(text)")
        }
    }

    @Test("a window is written back in its largest whole unit")
    func text() {
        #expect(ConfigurationDuration.text(604_800) == "7d")
        #expect(ConfigurationDuration.text(10_800) == "3h")
        #expect(ConfigurationDuration.text(5400) == "90m")
        #expect(ConfigurationDuration.text(45) == "45s")
        #expect(ConfigurationDuration.text(0) == "0")
    }

    @Test("closed-window and finished-window set each kind's window, in the defaults and per project")
    func decodes() throws {
        let result = try #require(decoded("""
            version = 1
            [defaults.pull-requests]
            closed-window = "30m"

            [defaults.issues]
            closed-window = "2d"

            [defaults.workflow-runs]
            finished-window = "45s"

            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            pull-requests = { closed-window = "12h" }
            issues = { closed-window = "0" }
            workflow-runs = { finished-window = "90m" }
            """))
        #expect(result.warnings.isEmpty)
        let config = result.configuration
        #expect(config.defaults.pullRequests.closedWindow == 1800)
        #expect(config.defaults.issues.closedWindow == 172_800)
        #expect(config.defaults.workflowRuns.finishedWindow == 45)
        let settings = config.settings(for: try #require(config.projects.first))
        #expect(settings.pullRequests.closedWindow == 43_200)
        #expect(settings.issues.closedWindow == 0)
        #expect(settings.workflowRuns.finishedWindow == 5400)
    }

    @Test("a bad window is rejected with its line, what's allowed, and the nearest spelling")
    func rejections() {
        let allowed = "a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\""
        func rejected(_ value: String, key: String = "closed-window", table: String = "pull-requests") -> [ConfigurationIssue] {
            rejection("version = 1\n[defaults.\(table)]\n\(key) = \(value)\n")
        }
        let cases: [(String, String)] = [
            ("\"30min\"", "`closed-window` must be \(allowed) (got \"30min\"; did you mean \"30m\"?)"),
            ("\"2 hours\"", "`closed-window` must be \(allowed) (got \"2 hours\"; did you mean \"2h\"?)"),
            ("\"1h30m\"", "`closed-window` must be \(allowed) (got \"1h30m\"; did you mean \"90m\"?)"),
            ("\"1.5h\"", "`closed-window` must be \(allowed) (got \"1.5h\"; did you mean \"90m\"?)"),
            ("\"30M\"", "`closed-window` must be \(allowed) (got \"30M\"; did you mean \"30m\"?)"),
            ("\"1w\"", "`closed-window` must be \(allowed) (got \"1w\"; did you mean \"7d\"?)"),
            ("\"30\"", "`closed-window` must be \(allowed) (got \"30\")"),
            ("\"5y\"", "`closed-window` must be \(allowed) (got \"5y\")"),
            ("\"\"", "`closed-window` must be \(allowed) (got \"\")"),
            ("\"-5m\"", "`closed-window` can't be negative (got \"-5m\")"),
            ("30", "`defaults.pull-requests.closed-window` must be a string: \(allowed)"),
        ]
        for (value, message) in cases {
            #expect(rejected(value) == [ConfigurationIssue(line: 3, message: message)], "\(value)")
        }
        #expect(rejected("\"3 hrs\"", key: "finished-window", table: "workflow-runs")
            == [ConfigurationIssue(line: 3, message: "`finished-window` must be \(allowed) (got \"3 hrs\"; did you mean \"3h\"?)")])
        #expect(rejection("[[projects]]\nslug = \"a\"\nrepositories = [\"o/a\"]\nissues = { closed-window = \"7 days\" }\n")
            == [ConfigurationIssue(line: 4, message: "`closed-window` must be \(allowed) (got \"7 days\"; did you mean \"7d\"?)")])
    }

    @Test("the schema's window pattern takes exactly what the reader takes")
    func schemaPattern() throws {
        let schema = try loadSchema()
        let definitions = try #require(schema["definitions"] as? [String: Any])
        var patterns: Set<String> = []
        for (kind, key) in [("pull-requests", "closed-window"), ("issues", "closed-window"), ("workflow-runs", "finished-window")] {
            let properties = try #require((definitions[kind] as? [String: Any])?["properties"] as? [String: Any])
            patterns.insert(try #require((properties[key] as? [String: Any])?["pattern"] as? String))
        }
        #expect(patterns.count == 1)
        let pattern = try #require(patterns.first)
        let samples = ["45s", "30m", "12h", "7d", "0", "0s", "007m", "30", "30min", "1h30m", "1.5h", "-5m", "", "30M", "2 h", " 3h", "3h "]
        for sample in samples {
            let reads = (try? ConfigurationDuration.parse(sample)) != nil
            let validates = sample.range(of: pattern, options: .regularExpression) != nil
            #expect(reads == validates, "`\(sample)`: the reader says \(reads), the schema \(validates)")
        }
    }
}
