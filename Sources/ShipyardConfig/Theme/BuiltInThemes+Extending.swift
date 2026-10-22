// The Harbor and Sunset themes' files, embedded so the app and the command
// read them with no file on disk. Each extends a Shipyard theme and keeps
// its appearance.

extension BuiltInThemes {
    static let harborSource = #"""
    # Harbor: a blue-green accent over system-like surfaces with glass.
    # It extends Shipyard Light, so it is light too, and changes only the
    # accent, the tints and the radii.
    name = "Harbor"
    version = 1
    extends = "Shipyard Light"
    description = "Shipyard Light's structure with a blue-green accent and softer corners; light."

    [palette]
    accent = "#0E7C86"

    [accent]
    soft = "#0E7C8626"

    [row]
    selected = "#0E7C8626"

    [surface]
    header = "#EAF2F3"

    [shape]
    small = 8
    medium = 10
    large = 14
    """#

    static let sunsetSource = #"""
    # Sunset: an orange accent over Shipyard Dark. It extends Shipyard Dark,
    # so it is dark too. Failed is a rose red, so the attention dot's two
    # colours never read as one.
    name = "Sunset"
    version = 1
    extends = "Shipyard Dark"
    description = "Shipyard Dark with an orange accent and a rose red for failed; dark."

    [palette]
    orange = "#FB923C"
    rose = "#F0506E"

    [accent]
    accent = "orange"

    [text]
    on-accent = "#1a0b02"

    [phase]
    failed = "rose"

    [signal]
    attention = "orange"
    """#
}
