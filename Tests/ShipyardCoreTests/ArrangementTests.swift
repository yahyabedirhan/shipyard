import Foundation
@testable import ShipyardCore
import Testing

@Suite("Arrangement")
struct ArrangementTests {
    /// Friday 2026-09-25 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_337_600)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    /// Weeks start on Monday, in UTC, so the buckets don't depend on the machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func item(
        _ number: Int,
        _ kind: ItemKind = .pullRequest,
        state: ItemState = .open,
        repository: String = "yahyabedirhan/shipyard",
        author: String = "yabepa",
        title: String? = nil,
        created: TimeInterval = 0,
        updated: TimeInterval = 0,
        closed: TimeInterval? = nil
    ) -> Item {
        Item(
            kind: kind,
            repository: repository,
            number: number,
            title: title ?? "Item \(number)",
            url: URL(string: "https://github.com/\(repository)/\(kind.rawValue)/\(number)")!,
            author: author,
            authorKind: .other,
            state: state,
            createdAt: now.addingTimeInterval(-created),
            updatedAt: now.addingTimeInterval(-updated),
            closedAt: closed.map { now.addingTimeInterval(-$0) }
        )
    }

    private func arrange(
        _ items: [Item],
        groupBy: GroupBy = .kind,
        subsections: Bool? = nil,
        sortBy: SortBy = .updated,
        showFirst: Int = 0,
        layout: MenuLayout = .list,
        expanded: Set<GroupID> = []
    ) -> [RowGroup] {
        Arrangement.groups(
            items,
            project: "shipyard",
            settings: ArrangementSettings(groupBy: groupBy, subsections: subsections, sortBy: sortBy, showFirst: showFirst),
            layout: layout,
            expanded: expanded,
            now: now,
            calendar: calendar
        )
    }

    private func numbers(_ groups: [RowGroup]) -> [[Int]] {
        groups.map { $0.rows.map(\.number) }
    }

    // MARK: - The default: today's grouping

    @Test("by default: pull requests, issues, runs; open by last update, then closed by when they closed")
    func defaultIsToday() {
        let items = [
            item(1, .issue, updated: 3 * hour),
            item(2, state: .merged, updated: hour, closed: 5 * hour),
            item(3, updated: 2 * hour),
            item(4, .workflowRun, state: .running, updated: hour),
            item(5, state: .closed, updated: 4 * hour, closed: 4 * hour),
            item(6, updated: hour),
        ]

        let groups = arrange(items)

        #expect(groups.map(\.id.key) == [.kind(.pullRequest), .kind(.issue), .kind(.workflowRun)])
        #expect(numbers(groups) == [[6, 3, 5, 2], [1], [4]])
        #expect(groups.map(\.title) == ["Pull requests", "Issues", "Runs"])
        #expect(groups.map(\.id.project) == ["shipyard", "shipyard", "shipyard"])
    }

    @Test("no items make no groups")
    func noItems() {
        for groupBy in GroupBy.allCases {
            #expect(arrange([], groupBy: groupBy).isEmpty)
        }
    }

    // MARK: - Grouping

    @Test("by repository: A to Z, ignoring case")
    func byRepository() {
        let items = [
            item(1, repository: "yahyabedirhan/skills"),
            item(2, repository: "Acme/web"),
            item(3, repository: "yahyabedirhan/shipyard"),
            item(4, repository: "yahyabedirhan/skills", updated: -hour),
        ]

        let groups = arrange(items, groupBy: .repository)

        #expect(groups.map(\.title) == ["Acme/web", "yahyabedirhan/shipyard", "yahyabedirhan/skills"])
        #expect(numbers(groups) == [[2], [3], [4, 1]])
    }

    @Test("by author: A to Z, each titled with its login")
    func byAuthor() {
        let items = [
            item(1, author: "octocat"),
            item(2, author: "dependabot[bot]"),
            item(3, author: "Yabepa"),
        ]

        let groups = arrange(items, groupBy: .author)

        #expect(groups.map(\.title) == ["@dependabot[bot]", "@octocat", "@Yabepa"])
        #expect(groups.map(\.id.key) == [.author("dependabot[bot]"), .author("octocat"), .author("Yabepa")])
    }

    @Test("by date: Today, Yesterday, This week, This month, Older, newest first")
    func byDate() {
        // Friday the 25th at noon: yesterday is Thursday, the week began
        // Monday the 21st, the month on the 1st.
        let items = [
            item(1, updated: 40 * day),
            item(2, updated: 11 * hour),
            item(3, updated: 13 * hour),
            item(4, updated: 3 * day),
            item(5, updated: 10 * day),
            item(6, updated: -5 * 60),
        ]

        let groups = arrange(items, groupBy: .date)

        #expect(groups.map(\.title) == ["Today", "Yesterday", "This week", "This month", "Older"])
        #expect(numbers(groups) == [[6, 2], [3], [4], [5], [1]])
    }

    @Test("by date buckets by the sort-by date: when created, else when last updated (sorting by title too)")
    func dateFollowsSortBy() {
        let items = [item(1, created: 3 * day, updated: hour)]

        #expect(arrange(items, groupBy: .date, sortBy: .created).map(\.title) == ["This week"])
        #expect(arrange(items, groupBy: .date, sortBy: .updated).map(\.title) == ["Today"])
        #expect(arrange(items, groupBy: .date, sortBy: .title).map(\.title) == ["Today"])
    }

    @Test("a closed item's date is when it closed")
    func closedBucketsByClosing() {
        let items = [item(1, state: .merged, updated: hour, closed: 30 * hour)]

        #expect(arrange(items, groupBy: .date).map(\.title) == ["Yesterday"])
    }

    @Test("none makes one untitled group, never with a header")
    func noGrouping() {
        let items = [item(1, .issue, updated: hour), item(2, updated: 2 * hour), item(3, .workflowRun, state: .running)]

        let groups = arrange(items, groupBy: .none, subsections: true)

        #expect(groups.count == 1)
        #expect(groups[0].id.key == .ungrouped)
        #expect(groups[0].title == "")
        #expect(groups[0].showsHeader == false)
        #expect(numbers(groups) == [[3, 1, 2]])
    }

    // MARK: - Sorting

    @Test("sort-by created: newest created first, open before closed")
    func sortByCreated() {
        let items = [
            item(1, created: 3 * hour, updated: 0),
            item(2, created: hour, updated: 5 * hour),
            item(3, state: .closed, created: 0, updated: 0, closed: 0),
        ]

        #expect(numbers(arrange(items, sortBy: .created)) == [[2, 1, 3]])
    }

    @Test("sort-by title: A to Z in natural order, open before closed")
    func sortByTitle() {
        let items = [
            item(1, title: "fix: item 10"),
            item(2, title: "Add docs"),
            item(3, title: "fix: item 9"),
            item(4, state: .merged, title: "A merged change", closed: 0),
        ]

        #expect(numbers(arrange(items, sortBy: .title)) == [[2, 3, 1, 4]])
    }

    @Test("items that sort equal keep the order they came in")
    func stable() {
        let items = [item(3), item(1), item(2)]

        #expect(numbers(arrange(items)) == [[3, 1, 2]])
    }

    // MARK: - Subheaders or dividers

    @Test("unset, subsections keep each layout's look: dividers in the list, subheaders in a tab")
    func subsectionsDefaultByLayout() {
        let items = [item(1), item(2, .issue)]

        #expect(arrange(items, layout: .list).map(\.showsHeader) == [false, false])
        #expect(arrange(items, layout: .tabs).map(\.showsHeader) == [true, true])
    }

    @Test("a subsections value applies to both layouts")
    func subsectionsSet() {
        let items = [item(1), item(2, .issue)]

        #expect(arrange(items, subsections: true, layout: .list).map(\.showsHeader) == [true, true])
        #expect(arrange(items, subsections: false, layout: .tabs).map(\.showsHeader) == [false, false])
    }

    @Test("a group counts its rows that need attention")
    func attentionCount() {
        let rows = [MenuRow(item(1), needsAttention: true), MenuRow(item(2)), MenuRow(item(3, .issue), needsAttention: true)]

        let groups = Arrangement.groups(rows: rows, project: "shipyard", settings: ArrangementSettings(), layout: .list, now: now)

        #expect(groups.map(\.attentionCount) == [1, 1])
    }

    // MARK: - Show more

    /// Seven open pull requests, #1 the newest, and two issues.
    private var sevenAndTwo: [Item] {
        (1...7).map { item($0, updated: Double($0) * hour) } + [item(8, .issue), item(9, .issue)]
    }

    private let pullRequests = GroupID(project: "shipyard", key: .kind(.pullRequest))

    @Test("show-first 5 shows a group of seven's first five rows and hides two, in order; a shorter group isn't capped")
    func showFirstCaps() {
        let groups = arrange(sevenAndTwo, showFirst: 5)

        #expect(numbers(groups) == [[1, 2, 3, 4, 5], [8, 9]])
        #expect(groups[0].hiddenRows.map(\.number) == [6, 7])
        #expect(groups[0].hiddenCount == 2)
        #expect(groups[0].allRows.map(\.number) == [1, 2, 3, 4, 5, 6, 7])
        #expect(groups[0].hasShowMore)
        #expect(!groups[0].isExpanded)
        #expect(!groups[1].hasShowMore)
        #expect(PanelText.showMore(groups[0]) == "Show 2 more")
    }

    @Test("an expanded group shows every row and a Show less row")
    func expandedShowsAll() {
        let groups = arrange(sevenAndTwo, showFirst: 5, expanded: [pullRequests])

        #expect(numbers(groups) == [[1, 2, 3, 4, 5, 6, 7], [8, 9]])
        #expect(groups[0].hiddenCount == 0)
        #expect(groups[0].isExpanded)
        #expect(groups[0].hasShowMore)
        #expect(PanelText.showMore(groups[0]) == "Show less")
    }

    @Test("show-first 0, or a group no longer than the cap, has no Show more row, expanded or not")
    func noCap() {
        for groups in [
            arrange(sevenAndTwo),
            arrange(sevenAndTwo, showFirst: 7, expanded: [pullRequests]),
            arrange(sevenAndTwo, showFirst: 0, expanded: [pullRequests]),
        ] {
            #expect(groups.map(\.hasShowMore) == [false, false])
            #expect(groups.map(\.isExpanded) == [false, false])
            #expect(groups.map(\.hiddenCount) == [0, 0])
        }
    }

    @Test("with group-by none the cap applies to the whole project")
    func capsWholeProject() {
        let groups = arrange(sevenAndTwo, groupBy: .none, showFirst: 5)

        #expect(groups.count == 1)
        #expect(groups[0].rows.count == 5)
        #expect(groups[0].hiddenCount == 4)
        #expect(PanelText.showMore(groups[0]) == "Show 4 more")
    }

    @Test("the cap applies under subheaders and after dividers alike, in both layouts")
    func capsEitherLook() {
        for subsections in [true, false] {
            for layout in MenuLayout.allCases {
                let groups = arrange(sevenAndTwo, subsections: subsections, showFirst: 5, layout: layout)
                #expect(groups[0].showsHeader == subsections)
                #expect(groups[0].hiddenCount == 2)
            }
        }
    }

    @Test("a group's attention count includes the rows its cap hides")
    func attentionCountsHidden() {
        let rows = (1...4).map { MenuRow(item($0, updated: Double($0) * hour), needsAttention: $0 > 2) }

        let groups = Arrangement.groups(
            rows: rows, project: "shipyard", settings: ArrangementSettings(showFirst: 2), layout: .list, now: now
        )

        #expect(groups[0].rows.map(\.number) == [1, 2])
        #expect(groups[0].attentionCount == 2)
    }

    // MARK: - Words

    @Test("a subheader shows a kind or a date in capitals, a repository or a login as written")
    func headerWords() {
        let groups = arrange([item(1, repository: "Acme/Web", author: "OctoCat")], groupBy: .repository)
            + arrange([item(1, author: "OctoCat")], groupBy: .author)
            + arrange([item(1)], groupBy: .date)
            + arrange([item(1)])

        #expect(groups.map(PanelText.groupHeader) == ["Acme/Web", "@OctoCat", "TODAY", "PULL REQUESTS"])
    }
}
