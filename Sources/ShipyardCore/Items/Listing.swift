import Foundation

/// The one place that decides what a project has (ADR 0003). Pure.
///
/// A project's listing is the snapshot's items for it that pass every one of
/// its filters, combined with AND: the kind is shown, a closed (or finished)
/// item is inside its window, a draft is allowed, and the author passes the
/// kind's `authors`. The menu model, the attention counts and the
/// notification step all read listings, so an item the filters leave out is
/// never shown, counted or notified. A new filter is one more check here.
public enum Listing {
    /// The items `project` lists from `snapshot`, in the snapshot's order.
    /// `viewer` is the signed-in login, which `me` matches; `now` is what the
    /// windows count back from.
    public static func items(for project: ProjectSettings, in snapshot: Snapshot, viewer: String?, now: Date) -> [Item] {
        (snapshot.items[project.name] ?? []).filter { lists($0, project: project, viewer: viewer, now: now) }
    }

    /// Every project's listing, by project name, for the projects the
    /// snapshot has an entry for; a project it has none for (added since it
    /// was fetched) has no listing yet.
    public static func listings(for projects: [ProjectSettings], in snapshot: Snapshot, now: Date) -> [String: [Item]] {
        var listings: [String: [Item]] = [:]
        for project in projects where snapshot.items[project.name] != nil {
            listings[project.name] = items(for: project, in: snapshot, viewer: snapshot.viewerLogin, now: now)
        }
        return listings
    }

    /// Whether `project` lists `item`.
    static func lists(_ item: Item, project: ProjectSettings, viewer: String?, now: Date) -> Bool {
        project.shows(item.kind)
            && inWindow(item, project: project, now: now)
            && (item.state != .draft || project.pullRequests.drafts)
            && project.authors(of: item.kind).includes(item, viewer: viewer)
    }

    /// Open and running items always are; closed ones for their kind's
    /// closed window in days, finished runs for `finished-window-hours`,
    /// counted back from `now`. A window of 0 leaves them all out.
    private static func inWindow(_ item: Item, project: ProjectSettings, now: Date) -> Bool {
        guard !item.state.isActive else { return true }
        let window: TimeInterval = switch item.kind {
        case .pullRequest: TimeInterval(project.pullRequests.closedWindowDays) * 86_400
        case .issue: TimeInterval(project.issues.closedWindowDays) * 86_400
        case .workflowRun: TimeInterval(project.workflowRuns.finishedWindowHours) * 3600
        }
        guard window > 0, let closedAt = item.closedAt else { return false }
        return closedAt >= now.addingTimeInterval(-window)
    }
}
