import ShipyardCore
import Testing

private let picked = [NewProject(name: "shop", repositories: ["yabepa/shop"])]

@Suite("Preset choice")
struct PresetChoiceTests {
    @Test("nothing goes on until a preset is chosen")
    func nothingChosen() {
        var choice = PresetChoice()
        #expect(!choice.canContinue)
        let proceeded = choice.proceed()
        #expect(!proceeded)
        #expect(choice.step == .preset)
    }

    @Test("my-agents goes on to the repository picker and writes the picked projects")
    func myAgents() {
        var choice = PresetChoice(preset: .myAgents)
        #expect(!choice.offersOwned)
        let proceeded = choice.proceed()
        #expect(!proceeded)
        #expect(choice.step == .repositories)
        #expect(choice.projects(from: picked) == picked)

        choice.back()
        #expect(choice.step == .preset)
        #expect(choice.preset == .myAgents)
    }

    @Test("incoming-contributions watches owned by default and is written at once, with no projects of its own")
    func incomingOwned() {
        var choice = PresetChoice(preset: .incomingContributions)
        #expect(choice.offersOwned)
        #expect(choice.watchesOwned)
        let proceeded = choice.proceed()
        #expect(proceeded)
        #expect(choice.step == .preset)
        #expect(choice.projects(from: picked).isEmpty)
    }

    @Test("incoming-contributions with picking goes on to the repository picker")
    func incomingPicked() {
        var choice = PresetChoice(preset: .incomingContributions)
        choice.watchesOwned = false
        let proceeded = choice.proceed()
        #expect(!proceeded)
        #expect(choice.step == .repositories)
        #expect(choice.projects(from: picked) == picked)
    }

    @Test("review-queue needs nothing and is written at once")
    func reviewQueue() {
        var choice = PresetChoice(preset: .reviewQueue)
        #expect(!choice.offersOwned)
        #expect(!choice.needsRepositories)
        let proceeded = choice.proceed()
        #expect(proceeded)
        #expect(choice.projects(from: picked).isEmpty)
    }
}
