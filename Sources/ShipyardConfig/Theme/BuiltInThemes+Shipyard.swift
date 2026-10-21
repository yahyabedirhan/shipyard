// The Shipyard theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let shipyardSource = #"""
    # Shipyard: the default theme.
    # System glass and text for the chrome and the tabs layout,
    # a quiet monochrome list with one blue accent.
    name = "Shipyard"
    version = 1
    description = "The default: system glass and text, quiet state icons, one blue accent."

    # Raw colors, named once. Tokens below refer to them by name.
    [light.palette]
    accent = "#2F6BDE"
    quiet = "#6B6B72"
    quiet-dim = "#6B6B72b3"
    ok = "#2E8B4Eb3"
    bad = "#D1242F"
    warn = "#9A6700"
    band = "#F8F8F9"
    on-accent = "#ffffff"
    [dark.palette]
    accent = "#6D9CFF"
    quiet = "#9A9AA2"
    quiet-dim = "#9A9AA2b3"
    ok = "#4CB868b3"
    bad = "#F2655F"
    warn = "#D9A02A"
    band = "#29292C"
    # White text on the accent, in dark as in light.
    on-accent = "#ffffff"

    [any.surface]
    window = "system"
    panel = "system"
    header = "band"
    chrome = "system"
    raised = "system"
    field = "system"
    track = "system"

    [any.text]
    primary = "system"
    secondary = "system"
    tertiary = "system"
    seen = "system"
    on-accent = "on-accent"

    [any.accent]
    accent = "accent"
    soft = "system"

    [any.line]
    separator = "system"
    border = "system"

    [any.row]
    hover = "system"
    pressed = "system"
    selected = "system"

    # Open, draft, merged and closed rows are quiet ink; their icons say which.
    [any.state]
    open = "quiet"
    draft = "quiet"
    merged = "quiet"
    closed = "quiet-dim"
    success = "ok"
    failure = "bad"
    pending = "warn"
    running = "warn"
    neutral = "quiet"

    [any.signal]
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
