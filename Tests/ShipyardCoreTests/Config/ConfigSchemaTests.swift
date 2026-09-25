import Foundation
@testable import ShipyardCore
import Testing
import TOMLDecoder

// The published schema (`schema/config.schema.json`) is the contract agents
// validate against with `taplo check`. These tests check it with a small
// validator that covers the JSON Schema keywords the file uses.

private func loadSchema() throws -> [String: Any] {
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
private func violations(_ text: String, schema: [String: Any]) throws -> [String] {
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
private func declaredPaths(_ raw: [String: Any], root: [String: Any], at path: String = "") -> Set<String> {
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
        #expect(try violations(try designExample(), schema: schema) == [])
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
        // keys are the ones shipyard reads.
        #expect(declaredPaths(schema, root: schema) == setPaths(everyKeyValue))
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
        #expect(enumValues(["notification-rule", "properties", "authors"], in: definitions) == AuthorFilter.allCases.map(\.rawValue))
        #expect(enumValues(["workflow-runs", "properties", "branches"], in: definitions) == WorkflowRunBranches.allCases.map(\.rawValue))
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(enumValues(["menu-bar", "properties", "count"], in: properties) == MenuBarCount.allCases.map(\.rawValue))
        #expect(enumValues(["rate-limit", "properties", "show"], in: properties) == RateLimitDisplay.allCases.map(\.rawValue))
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
            [[projects]]
            name = "a"
            repositories = ["not-a-slug"]
            issues = { closed-window-days = -1 }
            """
        let found = Set(try violations(bad, schema: schema))
        #expect(found == [
            ".refresh-interval-seconds: below 30",
            ": unknown key colour",
            ".rate-limit.max-share-percent: above 50",
            ".defaults.notifications[0].event: pr.openned not in enum",
            ".projects[0].repositories[0]: not-a-slug doesn't match ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$",
            ".projects[0].issues.closed-window-days: below 0",
        ])
    }

    @Test("a new file's schema line points at the published schema")
    func schemaLine() throws {
        let schema = try loadSchema()
        #expect(schema["$id"] as? String == Configuration.schemaURL)
        #expect(Configuration.header.hasPrefix("#:schema \(Configuration.schemaURL)\n"))
        #expect(try designExample().hasPrefix("#:schema \(Configuration.schemaURL)\n"))
    }
}
