// The Graphite theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let graphiteSource = #"""
    # Graphite: a dark-leaning neutral. Flat surfaces, steel-blue accent.
    name = "Graphite"
    version = 1
    description = "Dark-leaning neutral gray with a steel-blue accent; flat, no glass."

    [dark.palette]
    ground = "#1C1C1E"
    band = "#252528"
    lift = "#35353A"
    ink = "#ECECEE"
    ink-2 = "#A8A8B0"
    ink-3 = "#8A8A92"
    ink-seen = "#B8B8C0"
    line = "#ffffff14"
    line-strong = "#ffffff24"
    wash = "#ffffff0d"
    press = "#ffffff1a"
    accent = "#6D9CFF"
    on-accent = "#0B1020"
    good = "#5FB27C"
    bad = "#F2655F"
    warn = "#D9A02A"
    quiet = "#9A9AA2"
    violet = "#A68BE0"
    [light.palette]
    ground = "#F2F2F3"
    band = "#E8E8EA"
    lift = "#FFFFFF"
    ink = "#1D1D20"
    ink-2 = "#55555D"
    ink-3 = "#6E6E76"
    ink-seen = "#44444B"
    line = "#00000014"
    line-strong = "#00000024"
    wash = "#0000000a"
    press = "#00000014"
    accent = "#3A5FA8"
    on-accent = "#ffffff"
    good = "#2E7D4A"
    bad = "#C62828"
    warn = "#8A5A00"
    quiet = "#62626A"
    violet = "#6E4FB0"

    [any.surface]
    window = "ground"
    panel = "ground"
    header = "band"
    chrome = "band"
    raised = "lift"
    field = "wash"
    track = "wash"

    [any.text]
    primary = "ink"
    secondary = "ink-2"
    tertiary = "ink-3"
    seen = "ink-seen"
    on-accent = "on-accent"

    [any.accent]
    accent = "accent"
    soft = "press"

    [any.line]
    separator = "line"
    border = "line-strong"

    [any.row]
    hover = "wash"
    pressed = "press"
    selected = "press"

    [any.state]
    open = "good"
    draft = "quiet"
    merged = "violet"
    closed = "bad"
    success = "good"
    failure = "bad"
    pending = "warn"
    running = "warn"
    neutral = "quiet"

    [any.signal]
    attention = "accent"
    lease = "warn"

    [density]
    preset = "regular"

    [shape]
    small = 4
    medium = 6
    large = 8

    [material]
    style = "flat"
    """#
}
