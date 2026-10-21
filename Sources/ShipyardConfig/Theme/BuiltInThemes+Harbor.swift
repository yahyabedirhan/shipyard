// The Harbor theme's file, embedded so the app and the command read it
// with no file on disk.

extension BuiltInThemes {
    static let harborSource = #"""
    # Harbor: a blue-green accent over system-like surfaces with glass.
    # It extends Shipyard and changes only the accent, the tints and the radii.
    name = "Harbor"
    version = 1
    extends = "Shipyard"
    description = "Shipyard's structure with a blue-green accent and softer corners."

    [light.palette]
    accent = "#0E7C86"
    [dark.palette]
    accent = "#3CC3C9"

    [light.accent]
    soft = "#0E7C8626"
    [dark.accent]
    soft = "#3CC3C933"

    [dark.text]
    on-accent = "#04201F"

    [light.row]
    selected = "#0E7C8626"
    [dark.row]
    selected = "#3CC3C933"

    [light.surface]
    header = "#EAF2F3"
    [dark.surface]
    header = "#1E2A2B"

    [shape]
    small = 8
    medium = 10
    large = 14
    """#
}
