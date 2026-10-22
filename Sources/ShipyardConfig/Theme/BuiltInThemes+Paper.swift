// The Paper Light theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let paperLightSource = #"""
    # Paper Light: warm cream surfaces and brown ink, a terracotta accent.
    # Failed is a crimson, so the attention dot's two colours read apart.
    name = "Paper Light"
    version = 1
    description = "Warm paper with brown ink and a terracotta accent; light."

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
    crimson = "#A3203C"
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
    failed = "crimson"
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
    low = "amber"
    exhausted = "failed"

    [states.ping]
    open = "quiet"

    [states.note]
    open = "quiet"

    # The attention dot: the accent for a new or changed row; while a pull
    # request's checks fail, attention-failed, which is failed's colour unless set.
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
