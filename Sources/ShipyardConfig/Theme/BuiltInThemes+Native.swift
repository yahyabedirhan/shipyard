// The Native theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let nativeSource = #"""
    # Native: every token is the matching macOS semantic color.
    # It follows the system accent and the system light or dark setting.
    name = "Native"
    version = 1
    description = "The system's own colors: semantic fills, labels and the user's accent."

    [surface]
    window = "system"
    panel = "system"
    header = "system"
    chrome = "system"
    raised = "system"
    field = "system"
    track = "system"

    [text]
    primary = "system"
    secondary = "system"
    tertiary = "system"
    seen = "system"
    on-accent = "system"

    [accent]
    accent = "system"
    soft = "system"

    [line]
    separator = "system"
    border = "system"

    [row]
    hover = "system"
    pressed = "system"
    selected = "system"

    # Where each state is in its life: active is green, done purple,
    # failed red, and quiet grey.
    [phase]
    active = "system"
    done = "system"
    failed = "system"
    quiet = "system"

    # Each kind's states, by phase. A state can name its own colour instead.
    [states.pull-request]
    open = "active"
    draft = "quiet"
    merged = "done"
    closed = "failed"

    [states.issue]
    open = "active"
    closed = "done"

    [states.run]
    running = "active"
    succeeded = "done"
    failed = "failed"

    [states.check]
    pending = "active"
    passed = "done"
    failed = "failed"

    [states.review]
    review-required = "active"
    approved = "done"
    changes-requested = "failed"

    # The rate limit's low is a warning, not a phase.
    [states.rate]
    normal = "active"
    low = "system"
    exhausted = "failed"

    [states.ping]
    open = "quiet"

    [states.note]
    open = "quiet"

    [signal]
    attention = "system"
    lease = "system"

    [font]
    family = "system"
    size = 12

    [density]
    preset = "regular"

    [shape]
    small = 6
    medium = 8
    large = 10

    [material]
    style = "glass"
    """#
}
