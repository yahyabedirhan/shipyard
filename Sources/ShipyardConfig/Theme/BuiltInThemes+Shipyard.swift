// The Shipyard theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let shipyardSource = #"""
    # Shipyard: the default theme.
    # System glass and text for the chrome and the tabs layout,
    # a quiet list with one blue accent and coloured state icons.
    name = "Shipyard"
    version = 1
    description = "The default: system glass and text, coloured state icons, one blue accent."

    # Raw colors, named once. Tokens below refer to them by name.
    [light.palette]
    accent = "#2F6BDE"
    grey = "#6B6B72"
    green = "#1F883D"
    purple = "#8250DF"
    bad = "#D1242F"
    warn = "#9A6700"
    band = "#F8F8F9"
    on-accent = "#ffffff"
    [dark.palette]
    accent = "#6D9CFF"
    grey = "#9A9AA2"
    green = "#4CB868"
    purple = "#A371F7"
    bad = "#F2655F"
    warn = "#D9A02A"
    band = "#29292C"
    # White text on the accent, in dark as in light.
    on-accent = "#ffffff"

    [surface]
    window = "system"
    panel = "system"
    header = "band"
    chrome = "system"
    raised = "system"
    field = "system"
    track = "system"

    [text]
    primary = "system"
    secondary = "system"
    tertiary = "system"
    seen = "system"
    on-accent = "on-accent"

    [accent]
    accent = "accent"
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
    active = "green"
    done = "purple"
    failed = "bad"
    quiet = "grey"

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
    low = "warn"
    exhausted = "failed"

    [states.ping]
    open = "quiet"

    [states.note]
    open = "quiet"

    [signal]
    attention = "accent"
    lease = "system"

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
