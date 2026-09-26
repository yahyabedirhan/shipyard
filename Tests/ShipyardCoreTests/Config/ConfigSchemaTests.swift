import Foundation
@testable import ShipyardCore
import Testing
import TOMLDecoder

// The published schema (`schema/config.schema.json`) is the contract agents
// validate against with `taplo check`. These tests check it with a small
// validator that covers the JSON Schema keywords the file uses.

func loadSchema() throws -> [String: Any] {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("schema/config.schema.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// A TOML value in the shape JSON Schema sees it.
private indirect enum Value {
    case object([String: Value])
    case array([Value])
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
}

private func value(of table: TOMLTable) -> Value {
    var object: [String: Value] = [:]
    for key in table.keys {
        if let sub = try? table.table(forKey: key) { object[key] = value(of: sub) }
        else if let array = try? table.array(forKey: key) { object[key] = value(of: array) }
        else if let string = try? table.string(forKey: key) { object[key] = .string(string) }
        else if let integer = try? table.integer(forKey: key) { object[key] = .integer(integer) }
        else if let bool = try? table.bool(forKey: key) { object[key] = .bool(bool) }
        else if let float = try? table.float(forKey: key) { object[key] = .float(float) }
    }
    return .object(object)
}

private func value(of array: TOMLArray) -> Value {
    .array((0..<array.count).compactMap { index in
        if let sub = try? array.table(atIndex: index) { return value(of: sub) }
        if let nested = try? array.array(atIndex: index) { return value(of: nested) }
        if let string = try? array.string(atIndex: index) { return .string(string) }
        if let integer = try? array.integer(atIndex: index) { return .integer(integer) }
        if let bool = try? array.bool(atIndex: index) { return .bool(bool) }
        if let float = try? array.float(atIndex: index) { return .float(float) }
        return nil
    })
}

/// The schema violations in `text`, as "path: problem".
func violations(_ text: String, schema: [String: Any]) throws -> [String] {
    var found: [String] = []
    check(value(of: try TOMLTable(source: text)), against: schema, root: schema, at: "", into: &found)
    return found
}

private func resolve(_ schema: [String: Any], root: [String: Any]) -> [String: Any] {
    guard let ref = schema["$ref"] as? String, ref.hasPrefix("#/definitions/"),
          let definitions = root["definitions"] as? [String: Any],
          let target = definitions[String(ref.dropFirst("#/definitions/".count))] as? [String: Any]
    else { return schema }
    return resolve(target, root: root)
}

private func check(_ value: Value, against raw: [String: Any], root: [String: Any], at path: String, into found: inout [String]) {
    let schema = resolve(raw, root: root)
    if let branches = schema["anyOf"] as? [[String: Any]] {
        let passes = branches.contains { branch in
            var inBranch: [String] = []
            check(value, against: branch, root: root, at: path, into: &inBranch)
            return inBranch.isEmpty
        }
        if !passes { found.append("\(path): matches none of anyOf") }
        return
    }
    let type = schema["type"] as? String
    switch value {
    case .object(let object):
        guard type == "object" else { return found.append("\(path): expected \(type ?? "?"), got a table") }
        let properties = schema["properties"] as? [String: Any] ?? [:]
        for key in schema["required"] as? [String] ?? [] where object[key] == nil {
            found.append("\(path): missing \(key)")
        }
        for (key, child) in object {
            if let childSchema = properties[key] as? [String: Any] {
                check(child, against: childSchema, root: root, at: path + "." + key, into: &found)
            } else if schema["additionalProperties"] as? Bool == false {
                found.append("\(path): unknown key \(key)")
            }
        }
    case .array(let elements):
        guard type == "array" else { return found.append("\(path): expected \(type ?? "?"), got an array") }
        if let minItems = schema["minItems"] as? Int, elements.count < minItems {
            found.append("\(path): fewer than \(minItems) items")
        }
        if schema["uniqueItems"] as? Bool == true {
            // Strings are all the file's unique lists hold; compared exactly, as JSON Schema does.
            let strings = elements.compactMap { element -> String? in
                guard case .string(let string) = element else { return nil }
                return string
            }
            if Set(strings).count != strings.count { found.append("\(path): items not unique") }
        }
        if let items = schema["items"] as? [String: Any] {
            for (index, element) in elements.enumerated() {
                check(element, against: items, root: root, at: "\(path)[\(index)]", into: &found)
            }
        }
    case .string(let string):
        guard type == "string" else { return found.append("\(path): expected \(type ?? "?"), got a string") }
        if let allowed = schema["enum"] as? [String], !allowed.contains(string) {
            found.append("\(path): \(string) not in enum")
        }
        if let minLength = schema["minLength"] as? Int, string.count < minLength {
            found.append("\(path): shorter than \(minLength)")
        }
        if let pattern = schema["pattern"] as? String,
           string.range(of: pattern, options: .regularExpression) == nil {
            found.append("\(path): \(string) doesn't match \(pattern)")
        }
    case .integer(let integer):
        guard type == "integer" || type == "number" else { return found.append("\(path): expected \(type ?? "?"), got an integer") }
        if let minimum = schema["minimum"] as? Int, Int(integer) < minimum { found.append("\(path): below \(minimum)") }
        if let maximum = schema["maximum"] as? Int, Int(integer) > maximum { found.append("\(path): above \(maximum)") }
        if let allowed = schema["enum"] as? [Int], !allowed.contains(Int(integer)) { found.append("\(path): \(integer) not in enum") }
    case .float:
        if type != "number" { found.append("\(path): expected \(type ?? "?"), got a float") }
    case .bool:
        if type != "boolean" { found.append("\(path): expected \(type ?? "?"), got a boolean") }
    }
}

/// Every property path the schema declares, e.g. `defaults.pull-requests.show`
/// and `projects[].notifications[].event`.
func declaredPaths(_ raw: [String: Any], root: [String: Any], at path: String = "") -> Set<String> {
    let schema = resolve(raw, root: root)
    var paths: Set<String> = []
    if let properties = schema["properties"] as? [String: Any] {
        for (key, child) in properties {
            let childPath = path.isEmpty ? key : path + "." + key
            paths.insert(childPath)
            paths.formUnion(declaredPaths(child as! [String: Any], root: root, at: childPath))
        }
    }
    if let items = schema["items"] as? [String: Any] {
        paths.formUnion(declaredPaths(items, root: root, at: path + "[]"))
    }
    return paths
}

/// The property paths the schema marks `deprecated`: old keys shipyard
/// still reads, with a warning, which a file without warnings doesn't set.
func deprecatedPaths(_ raw: [String: Any], root: [String: Any], at path: String = "") -> Set<String> {
    let schema = resolve(raw, root: root)
    var paths: Set<String> = []
    if let properties = schema["properties"] as? [String: Any] {
        for (key, child) in properties {
            let childPath = path.isEmpty ? key : path + "." + key
            let childSchema = child as! [String: Any]
            if childSchema["deprecated"] as? Bool == true { paths.insert(childPath) }
            paths.formUnion(deprecatedPaths(childSchema, root: root, at: childPath))
        }
    }
    if let items = schema["items"] as? [String: Any] {
        paths.formUnion(deprecatedPaths(items, root: root, at: path + "[]"))
    }
    return paths
}

/// Every key path set in a TOML value, in the same notation.
private func setPaths(_ value: Value, at path: String = "") -> Set<String> {
    switch value {
    case .object(let object):
        var paths: Set<String> = []
        for (key, child) in object {
            let childPath = path.isEmpty ? key : path + "." + key
            paths.insert(childPath)
            paths.formUnion(setPaths(child, at: childPath))
        }
        return paths
    case .array(let elements):
        return elements.reduce(into: []) { $0.formUnion(setPaths($1, at: path + "[]")) }
    default:
        return []
    }
}

@Suite("Configuration schema")
struct ConfigSchemaTests {
    @Test("the design's example file validates against the schema")
    func designExampleValidates() throws {
        let schema = try loadSchema()
        // The design's example file already uses settings that aren't built yet;
        // this wrapper comes off once the example validates.
        withKnownIssue {
            let found = try violations(try designExample(), schema: schema)
            #expect(found == [])
        }
    }

    @Test("a file setting every key validates against the schema")
    func everyKeyValidates() throws {
        #expect(try violations(everyKey, schema: try loadSchema()) == [])
    }

    @Test("the schema declares exactly the keys shipyard reads")
    func describesEveryKey() throws {
        let schema = try loadSchema()
        let everyKeyValue = value(of: try TOMLTable(source: everyKey))
        // `everyKey` decodes without warnings (see the decoding tests), so its
        // keys are the ones shipyard reads, besides the deprecated ones it
        // still reads with a warning.
        let deprecated = deprecatedPaths(schema, root: schema)
        #expect(deprecated == ["hide-authors"])
        #expect(declaredPaths(schema, root: schema) == setPaths(everyKeyValue).union(deprecated))
    }

    @Test("the old forms still validate, so taplo passes every file shipyard reads")
    func oldFormsValidate() throws {
        let old = """
            hide-authors = ["dependabot[bot]"]
            [[defaults.notifications]]
            event = "pr.opened"
            authors = "others"
            [[defaults.notifications]]
            event = "pr.merged"
            authors = "any"
            """
        #expect(try violations(old, schema: try loadSchema()) == [])
    }

    @Test("the schema's author selectors are the ones the reader takes")
    func authorSelectorPattern() throws {
        let schema = try loadSchema()
        let definitions = try #require(schema["definitions"] as? [String: Any])
        let selectors = try #require(definitions["author-selectors"] as? [String: Any])
        let items = try #require(selectors["items"] as? [String: Any])
        let pattern = try #require(items["pattern"] as? String)
        let samples = [
            "me", "others", "bots", "@octocat", "@dependabot[bot]", "@some-login-2",
            "any", "bots2", "Me", "owned", "o/r", "@", "@-x", "@two words", "@o/r", "@x[bot", "dependabot[bot]",
        ]
        for sample in samples {
            let reads = (try? AuthorSelector(parsing: sample)) != nil
            let validates = sample.range(of: pattern, options: .regularExpression) != nil
            #expect(reads == validates, "`\(sample)`: the reader says \(reads), the schema \(validates)")
        }
    }

    @Test("every key in the schema has a description")
    func everyKeyDescribed() throws {
        let schema = try loadSchema()
        func undescribed(_ raw: [String: Any], at path: String) -> [String] {
            var missing: [String] = []
            let resolved = resolve(raw, root: schema)
            for (key, child) in resolved["properties"] as? [String: Any] ?? [:] {
                let childSchema = child as! [String: Any]
                let childPath = path + "." + key
                if childSchema["description"] == nil && resolve(childSchema, root: schema)["description"] == nil {
                    missing.append(childPath)
                }
                missing += undescribed(childSchema, at: childPath)
            }
            if let items = resolved["items"] as? [String: Any] { missing += undescribed(items, at: path + "[]") }
            return missing
        }
        #expect(undescribed(schema, at: "") == [])
    }

    @Test("the schema's choices match the ones shipyard reads")
    func choicesMatch() throws {
        let schema = try loadSchema()
        let definitions = try #require(schema["definitions"] as? [String: Any])
        func enumValues(_ path: [String], in root: [String: Any]) -> [String]? {
            var node: [String: Any]? = root
            for key in path { node = node?[key] as? [String: Any] }
            return node?["enum"] as? [String]
        }
        #expect(enumValues(["notification-rule", "properties", "event"], in: definitions) == EventKind.allCases.map(\.rawValue))
        let ruleAuthors = try #require((definitions["notification-rule"] as? [String: Any])?["properties"] as? [String: Any])["authors"] as? [String: Any]
        let oldAuthors = (ruleAuthors?["anyOf"] as? [[String: Any]])?.compactMap { $0["enum"] as? [String] }
        #expect(oldAuthors == [NotificationRule.legacyAuthors])
        #expect(enumValues(["workflow-runs", "properties", "branches"], in: definitions) == WorkflowRunBranches.allCases.map(\.rawValue))
        for (kind, table) in [(ItemKind.pullRequest, "pull-requests"), (.issue, "issues"), (.workflowRun, "workflow-runs")] {
            #expect(enumValues([table, "properties", "states", "items"], in: definitions) == StateGroup.all(for: kind).map(\.rawValue))
        }
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(enumValues(["menu-bar", "properties", "count"], in: properties) == MenuBarCount.allCases.map(\.rawValue))
        #expect(enumValues(["menu", "properties", "layout"], in: properties) == MenuLayout.allCases.map(\.rawValue))
        #expect(enumValues(["rate-limit", "properties", "show"], in: properties) == RateLimitDisplay.allCases.map(\.rawValue))
        #expect(enumValues(["group-by"], in: definitions) == GroupBy.allCases.map(\.rawValue))
        #expect(enumValues(["sort-by"], in: definitions) == SortBy.allCases.map(\.rawValue))
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let schema = try loadSchema()
        let bad = """
            refresh-interval-seconds = 10
            colour = "red"
            [rate-limit]
            max-share-percent = 60
            [[defaults.notifications]]
            event = "pr.openned"
            authors = "everyone"
            [[projects]]
            name = "a"
            repositories = ["not-a-slug", "o/r", "o/r"]
            issues = { closed-window-days = -1, authors = { hide = ["bots2"] } }
            """
        let found = Set(try violations(bad, schema: schema))
        #expect(found == [
            ".refresh-interval-seconds: below 30",
            ": unknown key colour",
            ".rate-limit.max-share-percent: above 50",
            ".defaults.notifications[0].event: pr.openned not in enum",
            ".defaults.notifications[0].authors: matches none of anyOf",
            ".projects[0].repositories[0]: not-a-slug doesn't match ^([A-Za-z0-9-]+/([A-Za-z0-9._-]+|\\*)|owned|organizations|collaborator|anywhere)$",
            ".projects[0].repositories: items not unique",
            ".projects[0].issues.closed-window-days: below 0",
            ".projects[0].issues.authors.hide[0]: bots2 doesn't match ^(me|others|bots|@[A-Za-z0-9][A-Za-z0-9-]*(\\[bot\\])?)$",
        ])
    }

    @Test("a new file's commented header is a valid configuration, each example uncommented alone and all together too")
    func headerIsValid() throws {
        let schema = try loadSchema()
        let header = decoded(Configuration.header)
        #expect(header?.warnings == [])
        #expect(header?.configuration == Configuration())
        #expect(try violations(Configuration.header, schema: schema) == [])
        // The header shows settings as commented-out TOML (`# [menu]`,
        // `# layout = "list"`), each at its default; uncommenting any one
        // example, or all of them, must still read cleanly and mean the same.
        let examples = headerExamples()
        #expect(examples.count >= 7)
        for example in examples + [Set(examples.joined())] {
            let text = uncommenting(example)
            #expect(text != Configuration.header)
            let read = decoded(text)
            #expect(read?.warnings == [], "uncommenting lines \(example.sorted())")
            #expect(read?.configuration == Configuration(), "uncommenting lines \(example.sorted())")
            #expect(try violations(text, schema: schema) == [], "uncommenting lines \(example.sorted())")
        }
    }

    @Test("a new file's header shows the settings people reach for first")
    func headerShowsCommonSettings() throws {
        let table = try TOMLTable(source: uncommenting(Set(headerExamples().joined())))
        #expect(try table.table(forKey: "menu").string(forKey: "layout") == "list")
        #expect(try table.table(forKey: "menu-bar").string(forKey: "count") == "total")
        #expect(try table.table(forKey: "rate-limit").integer(forKey: "max-share-percent") == 10)
        let defaults = try table.table(forKey: "defaults")
        #expect(try defaults.string(forKey: "group-by") == "kind")
        #expect(try defaults.string(forKey: "sort-by") == "updated")
        let authors = try defaults.table(forKey: "pull-requests").table(forKey: "authors")
        #expect(try authors.array(forKey: "show").count == 0)
        #expect(try authors.array(forKey: "hide").count == 0)
        #expect(try defaults.table(forKey: "issues").bool(forKey: "show") == false)
        #expect(try defaults.table(forKey: "workflow-runs").bool(forKey: "show") == false)
        let rules = try defaults.array(forKey: "notifications")
        #expect(rules.count == 1)
        #expect(try rules.table(atIndex: 0).string(forKey: "event") == "pr.opened")
    }

    @Test("a new file's schema line points at the published schema")
    func schemaLine() throws {
        let schema = try loadSchema()
        #expect(schema["$id"] as? String == Configuration.schemaURL)
        #expect(Configuration.header.hasPrefix("#:schema \(Configuration.schemaURL)\n"))
        #expect(try designExample().hasPrefix("#:schema \(Configuration.schemaURL)\n"))
    }
}

/// The header's commented-out examples: each a run of consecutive setting
/// lines (`# [table]`, `# key = value`), as line indices.
private func headerExamples() -> [Set<Int>] {
    var examples: [Set<Int>] = []
    var current: Set<Int> = []
    for (index, line) in Configuration.header.components(separatedBy: "\n").enumerated() {
        let body = line.dropFirst(2)
        if line.hasPrefix("# ") && (body.hasPrefix("[") || body.contains(" = ")) {
            current.insert(index)
        } else if !current.isEmpty {
            examples.append(current)
            current = []
        }
    }
    if !current.isEmpty { examples.append(current) }
    return examples
}

/// The header with the lines at `indices` uncommented.
private func uncommenting(_ indices: Set<Int>) -> String {
    Configuration.header.components(separatedBy: "\n").enumerated().map { index, line in
        indices.contains(index) ? String(line.dropFirst(2)) : line
    }.joined(separator: "\n")
}
