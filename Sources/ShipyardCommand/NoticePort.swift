/// The port notices from other machines travel to (ADR 0010): the one the
/// app listens on when `config.toml` says so, and the one another
/// machine's `shipyard notify` sends to, unless each file's `[notices] port`
/// says otherwise. Here, below both files' readers, so their defaults agree.
public enum NoticePort {
    public static let `default` = 47420

    /// The ports either file accepts.
    public static let range = 1...65535
}
