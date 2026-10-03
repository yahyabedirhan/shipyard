import Foundation

/// The one place that decides what a project has (ADR 0003). Pure.
///
/// A project's listing is the snapshot's items for it, and the pings filed
/// under it, that pass every one of
/// its filters, combined with AND: the kind is shown, the item's state is
/// one of the kind's `states`, a closed (or finished) item, or a seen
/// ping, is inside its window, a draft is allowed, the author passes the kind's `authors`, and
/// with `review-requested` a pull request waits on the user's review. The
/// menu model, the attention counts and the
/// notification step all read listings, so an item the filters leave out is
/// never shown, counted or notified. A new filter is one more check here.
public enum Listing {
    /// The items `project` lists from `snapshot`, in the snapshot's order.
    /// For a project using `anywhere`, the fetch put the review search's
    /// pull requests among its items, so they pass the same checks.
    /// `viewer` is the signed-in login, which `me` matches; `now` is what the
    /// windows count back from.
    public static func items(for project: ProjectSettings, in snapshot: Snapshot, viewer: String?, now: Date) -> [Item] {
        (snapshot.items[project.name] ?? []).filter {
            lists($0, project: project, viewer: viewer, reviewRequested: snapshot.reviewRequested, now: now)
        }
    }

    /// Every project's listing, by project name: the snapshot's items for
    /// it, then the `pings` filed under it, each passing the project's
    /// filters. A project with neither (added since the snapshot was
    /// fetched, or before any was) has no listing yet; without a snapshot
    /// a project lists its pings alone, so they show before GitHub answers.
    ///
    /// A remote ping (`Ping.machine`) is filed as a local one is, under
    /// the projects it names; one filed under none of `projects` is listed
    /// by its machine instead, under the machine's label, with the
    /// settings `machines` gives it (`Configuration.settings(forMachine:)`).
    /// A machine with no such ping has no listing.
    ///
    /// Each ping's item carries the number `numbers` gave it in that
    /// section (`PingNumbers`), or none (0) before it has one.
    public static func listings(
        for projects: [ProjectSettings],
        in snapshot: Snapshot?,
        pings: [Ping] = [],
        machines: [ProjectSettings] = [],
        numbers: PingNumbers? = nil,
        now: Date
    ) -> [String: [Item]] {
        let sections = sections(of: pings, projects: projects.map(\.name), machines: machines.map(\.name))
        func filed(in section: String) -> [Item] {
            (sections[section] ?? []).map { ping in
                var item = ping.item
                item.number = numbers?.number(of: item.id, in: section) ?? 0
                return item
            }
        }
        var listings: [String: [Item]] = [:]
        for project in projects {
            let fetched = snapshot.flatMap { snapshot in
                snapshot.items[project.name] != nil ? items(for: project, in: snapshot, viewer: snapshot.viewerLogin, now: now) : nil
            }
            let filed = filed(in: project.name)
            guard fetched != nil || !filed.isEmpty else { continue }
            listings[project.name] = (fetched ?? []) + filed.filter {
                lists($0, project: project, viewer: snapshot?.viewerLogin, reviewRequested: [], now: now)
            }
        }
        for machine in machines {
            let unfiled = filed(in: machine.name)
            guard !unfiled.isEmpty else { continue }
            listings[machine.name] = unfiled.filter {
                lists($0, project: machine, viewer: snapshot?.viewerLogin, reviewRequested: [], now: now)
            }
        }
        return listings
    }

    /// The sections `pings` are filed in, by name, before any filter: each
    /// project in `projects` its pings name, and each machine in `machines`
    /// its remote pings filed under none of `projects`. A section with no
    /// ping is left out. Where `listings` lists them, and what the Mac
    /// numbers them in (`PingNumbers`).
    static func sections(of pings: [Ping], projects: [String], machines: [String]) -> [String: [Ping]] {
        var sections: [String: [Ping]] = [:]
        let names = Set(projects)
        for project in projects {
            let filed = pings.filter { $0.projects.contains(project) }
            if !filed.isEmpty { sections[project] = filed }
        }
        for machine in machines {
            let unfiled = pings.filter { $0.machine == machine && !$0.projects.contains(where: names.contains) }
            if !unfiled.isEmpty { sections[machine] = unfiled }
        }
        return sections
    }

    /// Whether `project` lists `item`. `reviewRequested` holds the open pull
    /// requests waiting on the viewer's review (the review search's).
    static func lists(_ item: Item, project: ProjectSettings, viewer: String?, reviewRequested: Set<String>, now: Date) -> Bool {
        project.shows(item.kind)
            && project.states(of: item.kind).contains(item.state.group)
            && inWindow(item, project: project, now: now)
            && (item.state != .draft || project.pullRequests.drafts)
            && project.authors(of: item.kind).includes(item, viewer: viewer)
            && (item.kind != .pullRequest || !project.pullRequests.reviewRequested || reviewRequested.contains(item.id))
    }

    /// Open and running items always are; closed ones for their kind's
    /// `closed-window`, finished runs for their `finished-window`,
    /// counted back from `now`. A window of 0 leaves them all out. A ping
    /// is while it's unseen, and for its `seen-window` once it's seen.
    private static func inWindow(_ item: Item, project: ProjectSettings, now: Date) -> Bool {
        if let ping = item.ping { return ping.isListed(seenWindow: project.pings.seenWindow, at: now) }
        guard !item.state.isActive else { return true }
        let window: TimeInterval = switch item.kind {
        case .pullRequest: project.pullRequests.closedWindow
        case .issue: project.issues.closedWindow
        case .workflowRun: project.workflowRuns.finishedWindow
        // A ping's window is its seen-window, above.
        case .ping: 0
        }
        guard window > 0, let closedAt = item.closedAt else { return false }
        return closedAt >= now.addingTimeInterval(-window)
    }
}
