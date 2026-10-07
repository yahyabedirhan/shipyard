import Foundation
import Observation

/// Whether the shipyard agent skill is installed, as the Shipyard Skill view
/// and the settings menu's mark show it. The skills CLI (`npx skills add …
/// -g`) records each skill it installs in `~/.agents/.skill-lock.json`, by
/// name with its source repository, and copies it to
/// `~/.agents/skills/<name>/`. The skill is installed when the lock file's
/// `shipyard` entry comes from `yahyabedirhan/shipyard`, or, with no such
/// entry, when `~/.agents/skills/shipyard/SKILL.md` exists (a copy put
/// there by hand). An entry from another source is some other skill named
/// shipyard, so its folder doesn't count.
@MainActor
@Observable
public final class SkillDetector {
    /// The repository the skill installs from, as the lock file names it.
    nonisolated public static let source = "yahyabedirhan/shipyard"

    /// Whether the skill was installed when last looked; `check()` looks again.
    public private(set) var isInstalled: Bool

    private let home: URL

    public init(home: URL) {
        self.home = home
        isInstalled = Self.isInstalled(home: home)
    }

    /// Looks again: an install may have finished, or the user may have
    /// installed or removed the skill in a terminal.
    public func check() {
        isInstalled = Self.isInstalled(home: home)
    }

    /// Whether the skill is installed under `home`.
    nonisolated public static func isInstalled(home: URL) -> Bool {
        let agents = home.appendingPathComponent(".agents", isDirectory: true)
        if let entry = lockEntry(in: agents.appendingPathComponent(".skill-lock.json", isDirectory: false)) {
            return entry.source == source
        }
        let skill = agents.appendingPathComponent("skills/shipyard/SKILL.md", isDirectory: false)
        return FileManager.default.fileExists(atPath: skill.path)
    }

    /// The lock file's shape, as far as the detector reads it.
    private struct Lock: Decodable {
        struct Entry: Decodable {
            var source: String?
        }

        var skills: [String: Entry]?
    }

    /// The lock file's `shipyard` entry; nil when there's no lock file, it
    /// isn't one, or it has no such entry.
    nonisolated private static func lockEntry(in file: URL) -> Lock.Entry? {
        guard let data = try? Data(contentsOf: file),
              let lock = try? JSONDecoder().decode(Lock.self, from: data)
        else { return nil }
        return lock.skills?["shipyard"]
    }
}
