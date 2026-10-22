// The Paper theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let paperSource = #"""
    # Paper: warm cream surfaces and brown ink, a terracotta accent.
    # It fills the light appearance; dark mode repeats it.
    name = "Paper"
    version = 1
    description = "Warm light paper with brown ink and a terracotta accent; light only."

    [light.palette]
    cream = "#FAF6EE"
    sand = "#F1EBDD"
    band = "#F4EEE0"
    white = "#FFFFFF"
    ink = "#2B2118"
    ink-2 = "#5E5242"
    ink-3 = "#7A6D5B"
    ink-seen = "#4A3F32"
    line = "#2B211814"
    line-strong = "#2B211828"
    wash = "#2B21180d"
    press = "#2B211819"
    terracotta = "#B4491E"
    terracotta-soft = "#B4491E26"
    green = "#3F7D4E"
    plum = "#7B4FA0"
    brick = "#B3322A"
    brick-dim = "#B3322Ab3"
    amber = "#8F5A00"
    gold = "#C99A00"
    grey = "#7A6D5B"

    [surface]
    window = "sand"
    panel = "cream"
    header = "band"
    chrome = "band"
    raised = "white"
    field = "wash"
    track = "press"

    [text]
    primary = "ink"
    secondary = "ink-2"
    tertiary = "ink-3"
    seen = "ink-seen"
    on-accent = "white"

    [accent]
    accent = "terracotta"
    soft = "terracotta-soft"

    [line]
    separator = "line"
    border = "line-strong"

    [row]
    hover = "wash"
    pressed = "press"
    selected = "terracotta-soft"

    # Where each state is in its life: active is green, done purple,
    # failed red, and quiet grey.
    [phase]
    active = "green"
    done = "plum"
    failed = "brick"
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

    # Checks, approvals, the rate limit, pings and notes.
    [state]
    success = "green"
    failure = "brick"
    pending = "amber"
    neutral = "grey"

    [signal]
    attention = "terracotta"
    lease = "gold"

    [density]
    preset = "comfortable"

    [shape]
    small = 6
    medium = 8
    large = 12

    [material]
    style = "flat"
    """#
}
