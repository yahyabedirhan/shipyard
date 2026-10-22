// The Midnight theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let midnightSource = #"""
    # Midnight: deep blue, dark only. Light mode repeats the dark colors.
    name = "Midnight"
    version = 1
    description = "Deep blue dark theme with a bright blue accent; dark only."

    [dark.palette]
    deep = "#0A1124"
    navy = "#0F1830"
    band = "#14203C"
    lift = "#22345E"
    ink = "#E6ECFA"
    ink-2 = "#A9B6D6"
    ink-3 = "#8392B8"
    ink-seen = "#BCC8E4"
    line = "#8fa8e01f"
    line-strong = "#8fa8e03d"
    wash = "#8fa8e014"
    press = "#8fa8e026"
    sky = "#5B9BFF"
    sky-soft = "#5B9BFF33"
    on-sky = "#06122B"
    mint = "#6FCF97"
    violet = "#B794F6"
    coral = "#FF7A85"
    sun = "#F2C14E"
    grey = "#8392B8"

    [surface]
    window = "deep"
    panel = "navy"
    header = "band"
    chrome = "deep"
    raised = "lift"
    field = "wash"
    track = "deep"

    [text]
    primary = "ink"
    secondary = "ink-2"
    tertiary = "ink-3"
    seen = "ink-seen"
    on-accent = "on-sky"

    [accent]
    accent = "sky"
    soft = "sky-soft"

    [line]
    separator = "line"
    border = "line-strong"

    [row]
    hover = "wash"
    pressed = "press"
    selected = "sky-soft"

    # Where each state is in its life: active is green, done purple,
    # failed red, and quiet grey.
    [phase]
    active = "mint"
    done = "violet"
    failed = "coral"
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
    low = "sun"
    exhausted = "failed"

    [states.ping]
    open = "quiet"

    [states.note]
    open = "quiet"

    [signal]
    attention = "sky"
    lease = "sun"

    [density]
    preset = "compact"

    [shape]
    small = 5
    medium = 7
    large = 10

    [material]
    style = "flat"
    """#
}
