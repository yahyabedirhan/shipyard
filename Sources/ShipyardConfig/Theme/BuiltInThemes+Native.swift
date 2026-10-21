// The Native theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let nativeSource = #"""
    # Native: every token is the matching macOS semantic color.
    # It follows the system accent and the system light or dark setting.
    name = "Native"
    version = 1
    description = "The system's own colors: semantic fills, labels and the user's accent."

    [any.surface]
    window = "system"
    panel = "system"
    header = "system"
    chrome = "system"
    raised = "system"
    field = "system"
    track = "system"

    [any.text]
    primary = "system"
    secondary = "system"
    tertiary = "system"
    seen = "system"
    on-accent = "system"

    [any.accent]
    accent = "system"
    soft = "system"

    [any.line]
    separator = "system"
    border = "system"

    [any.row]
    hover = "system"
    pressed = "system"
    selected = "system"

    [any.state]
    open = "system"
    draft = "system"
    merged = "system"
    closed = "system"
    success = "system"
    failure = "system"
    pending = "system"
    running = "system"
    neutral = "system"

    [any.signal]
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
