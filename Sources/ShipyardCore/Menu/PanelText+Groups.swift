import Foundation

// The words of a project's groups: their titles and the date buckets' names.
extension PanelText {
    /// A group's title: its kind ("Pull requests"), repository
    /// ("owner/name"), date bucket ("Today") or author ("@login"); empty
    /// for the one group of `group-by = "none"`, which has no header.
    public static func groupTitle(_ key: GroupKey) -> String {
        switch key {
        case .kind(let kind): kindGroup(kind)
        case .repository(let repository): repository
        case .date(let bucket): dateBucket(bucket)
        case .author(let login): "@\(login)"
        case .ungrouped: ""
        }
    }

    /// The title of a kind's group: the small header over its rows in a tab.
    public static func kindGroup(_ kind: ItemKind) -> String {
        switch kind {
        case .pullRequest: "Pull requests"
        case .issue: "Issues"
        case .workflowRun: "Runs"
        }
    }

    /// A date bucket's name.
    public static func dateBucket(_ bucket: DateBucket) -> String {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .older: "Older"
        }
    }

    /// A subheader's title as drawn: a kind or a date in capitals, as the
    /// tabs' kind headers always were; a repository or a login as written,
    /// since its letter case is part of the name.
    public static func groupHeader(_ group: RowGroup) -> String {
        switch group.id.key {
        case .kind, .date, .ungrouped: group.title.uppercased()
        case .repository, .author: group.title
        }
    }

    /// A subheader's tooltip: what a click does to it.
    public static func groupFoldHelp(_ group: RowGroup) -> String {
        "\(group.isFolded ? "Unfold" : "Fold") \(group.title)"
    }

    /// A subheader's state for VoiceOver.
    public static func groupFoldState(_ group: RowGroup) -> String {
        group.isFolded ? "Folded" : "Open"
    }
}
