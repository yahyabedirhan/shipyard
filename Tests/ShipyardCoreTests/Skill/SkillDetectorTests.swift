import Foundation
import ShipyardCore
import Testing

/// A home folder in a fresh temporary folder, where a test writes the
/// skills CLI's lock file and the installed skill's folder.
private struct Home {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-skill-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// `~/.agents/.skill-lock.json` with a `shipyard` entry from `source`,
    /// beside another skill, as the skills CLI writes it.
    func writeLock(shipyardSource source: String?) throws {
        let shipyard = source.map { #", "shipyard": {"source": "\#($0)", "sourceType": "github", "skillPath": "skills/shipyard/SKILL.md"}"# } ?? ""
        let text = #"{"version": 3, "skills": {"handoff": {"source": "someone/skills", "sourceType": "github"}\#(shipyard)}, "dismissed": {}}"#
        try write(text, to: ".agents/.skill-lock.json")
    }

    /// `~/.agents/skills/shipyard/SKILL.md`.
    func writeSkill() throws {
        try write("---\nname: shipyard\n---\n", to: ".agents/skills/shipyard/SKILL.md")
    }

    private func write(_ text: String, to path: String) throws {
        let file = url.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

@Suite("Finding the installed shipyard skill")
@MainActor
struct SkillDetectorTests {
    @Test("the lock file's shipyard entry from yahyabedirhan/shipyard means installed, with or without the folder")
    func lockEntry() throws {
        let home = try Home()
        defer { home.remove() }
        try home.writeLock(shipyardSource: "yahyabedirhan/shipyard")
        #expect(SkillDetector.isInstalled(home: home.url))
        try home.writeSkill()
        #expect(SkillDetector.isInstalled(home: home.url))
    }

    @Test("the skill's folder alone means installed: no lock file, or one without a shipyard entry")
    func folderOnly() throws {
        let home = try Home()
        defer { home.remove() }
        try home.writeSkill()
        #expect(SkillDetector.isInstalled(home: home.url))
        try home.writeLock(shipyardSource: nil)
        #expect(SkillDetector.isInstalled(home: home.url))
    }

    @Test("neither the entry nor the folder means not installed, as does a lock file that isn't JSON")
    func neither() throws {
        let home = try Home()
        defer { home.remove() }
        #expect(!SkillDetector.isInstalled(home: home.url))
        try home.writeLock(shipyardSource: nil)
        #expect(!SkillDetector.isInstalled(home: home.url))
        try Data("not json".utf8).write(to: home.url.appendingPathComponent(".agents/.skill-lock.json"))
        #expect(!SkillDetector.isInstalled(home: home.url))
    }

    @Test("a shipyard entry from another source is some other skill, even with its folder")
    func anotherSource() throws {
        let home = try Home()
        defer { home.remove() }
        try home.writeLock(shipyardSource: "someone/shipyard")
        #expect(!SkillDetector.isInstalled(home: home.url))
        try home.writeSkill()
        #expect(!SkillDetector.isInstalled(home: home.url))
    }

    @Test("the detector looks when made, and again on check, so the menu's mark follows an install or a removal")
    func check() throws {
        let home = try Home()
        defer { home.remove() }
        let detector = SkillDetector(home: home.url)
        #expect(!detector.isInstalled)
        try home.writeLock(shipyardSource: "yahyabedirhan/shipyard")
        #expect(!detector.isInstalled)
        detector.check()
        #expect(detector.isInstalled)
        #expect(SetupStatus(cli: .unlinked, skill: detector.isInstalled).isSetUp(.skill))
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(".agents"))
        detector.check()
        #expect(!detector.isInstalled)
    }
}
