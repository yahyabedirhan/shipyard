import ShipyardCore
import Testing

private let frontend = RepoSummary(slug: "yahyabedirhan/e-commerce-frontend")
private let backend = RepoSummary(slug: "yahyabedirhan/e-commerce-backend")
private let jobSearch = RepoSummary(slug: "yahyabedirhan/job-search")

@Suite("Project choices")
struct ProjectChoicesTests {
    @Test("each chosen repository is a project named after it, in the order chosen")
    func oneProjectPerRepository() {
        var choices = ProjectChoices(suggestions: [frontend, backend, jobSearch])
        #expect(choices.projects.isEmpty)
        #expect(!choices.canConfirm)

        choices.toggle(jobSearch)
        choices.toggle(frontend)

        #expect(choices.isChosen(jobSearch.slug))
        #expect(!choices.isChosen(backend.slug))
        #expect(choices.projects == [
            NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
            NewProject(name: "e-commerce-frontend", repositories: ["yahyabedirhan/e-commerce-frontend"]),
        ])
        #expect(choices.canConfirm)
    }

    @Test("repositories given the same project name are grouped into one project; an emptied one splits again")
    func grouping() {
        var choices = ProjectChoices(suggestions: [frontend, backend, jobSearch])
        choices.toggle(frontend)
        choices.toggle(jobSearch)
        choices.toggle(backend)

        choices.rename(frontend.slug, to: " e-commerce ")
        #expect(choices.choice(for: frontend.slug)?.name == "e-commerce")
        choices.rename(backend.slug, to: "e-commerce")

        #expect(choices.projects == [
            NewProject(name: "e-commerce", repositories: ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]),
            NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
        ])
        #expect(choices.projectNames == ["e-commerce", "job-search"])

        choices.toggle(frontend)
        #expect(choices.projects == [
            NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
            NewProject(name: "e-commerce", repositories: ["yahyabedirhan/e-commerce-backend"]),
        ])
    }

    @Test("a project without a name can't be added, and says so")
    func unnamed() {
        var choices = ProjectChoices(suggestions: [frontend])
        choices.toggle(frontend)
        choices.rename(frontend.slug, to: "  ")
        #expect(!choices.canConfirm)
        #expect(choices.hasUnnamedProject)
        choices.rename(frontend.slug, to: "shop")
        #expect(choices.canConfirm)
        #expect(!choices.hasUnnamedProject)
        #expect(choices.choice(for: "YahyaBedirhan/E-Commerce-Frontend")?.name == "shop")
    }

    @Test("two repositories with the same name from different owners aren't grouped by default")
    func sameNameDifferentOwners() {
        let fork = RepoSummary(slug: "friend/job-search")
        var choices = ProjectChoices(suggestions: [jobSearch, fork])
        choices.toggle(jobSearch)
        choices.toggle(fork)
        #expect(choices.projects == [
            NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
            NewProject(name: "friend/job-search", repositories: ["friend/job-search"]),
        ])
    }

    @Test("a typed repository is offered before the suggestions and chosen; one already offered is only chosen")
    func typed() {
        var choices = ProjectChoices(suggestions: [frontend, backend])
        let typed = RepoSummary(slug: "acme/storefront", isPrivate: true)

        choices.add(typed)
        choices.add(RepoSummary(slug: "YahyaBedirhan/E-Commerce-Backend"))
        choices.add(typed)

        #expect(choices.offered.map(\.slug) == ["acme/storefront", "yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"])
        #expect(choices.projects == [
            NewProject(name: "storefront", repositories: ["acme/storefront"]),
            NewProject(name: "e-commerce-backend", repositories: ["yahyabedirhan/e-commerce-backend"]),
        ])
    }

    @Test("suggestions that arrive late keep what was typed and chosen, without listing a repository twice")
    func lateSuggestions() {
        var choices = ProjectChoices()
        let typed = RepoSummary(slug: "acme/storefront")
        choices.add(typed)
        choices.add(jobSearch)

        choices.setSuggestions([frontend, jobSearch])

        #expect(choices.offered.map(\.slug) == ["acme/storefront", "yahyabedirhan/e-commerce-frontend", "yahyabedirhan/job-search"])
        #expect(choices.projects.map(\.name) == ["storefront", "job-search"])
    }
}
