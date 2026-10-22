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
    quiet = "#6B6B72"
    green = "#1F883D"
    purple = "#8250DF"
    ok = "#2E8B4Eb3"
    bad = "#D1242F"
    warn = "#9A6700"
    band = "#F8F8F9"
    on-accent = "#ffffff"
    [dark.palette]
    accent = "#6D9CFF"
    quiet = "#9A9AA2"
    green = "#4CB868"
    purple = "#A371F7"
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

    # Open, merged and closed each take their own hue; a draft stays quiet.
    # A running run is active, as an open item is, so it takes open's hue.
    [any.state]
    open = "green"
    draft = "quiet"
    merged = "purple"
    closed = "bad"
    success = "ok"
    failure = "bad"
    pending = "warn"
    running = "green"
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
