// The flat themes' files, Paper Dark, Heather and Brass, embedded so the
// app and the command read them with no file on disk. Each writes one
// appearance's palette under the same tables.

extension BuiltInThemes {
    static let paperDarkSource = #"""
    # Paper Dark: Paper Light's dark sibling, on a neutral near-black base
    # with cream ink and a beige accent. Beige reads as text on the panel,
    # and dark ink reads on a beige button.
    name = "Paper Dark"
    version = 1
    description = "Cream ink on a warm near-black, with a beige accent; dark."

    [dark.palette]
    ground = "#1A1617"
    paper = "#221C1D"
    band = "#2B2324"
    lift = "#372D2F"
    ink = "#EFE8DC"
    ink-2 = "#C4BCAE"
    ink-3 = "#9C9488"
    ink-seen = "#D6CFC3"
    line = "#EFE8DC14"
    line-strong = "#EFE8DC28"
    wash = "#EFE8DC0d"
    press = "#EFE8DC1a"
    accent = "#E3CFA8"
    accent-soft = "#E3CFA833"
    on-accent = "#241C12"
    green = "#86BE8F"
    violet = "#B49AD8"
    red = "#E8695F"
    grey = "#9C9488"
    warn = "#D9A441"
    gold = "#E3B341"

    """# + flatTables(done: "violet")

    static let heatherSource = #"""
    # Heather: a calm violet on a lavender-white panel. Done is a plum
    # magenta, so merged never reads as the accent.
    name = "Heather"
    version = 1
    description = "A calm violet on a lavender-white panel; light."

    [light.palette]
    ground = "#F2F0F6"
    paper = "#FAF9FC"
    band = "#EEEBF4"
    lift = "#FFFFFF"
    ink = "#241F2E"
    ink-2 = "#565066"
    ink-3 = "#6E6780"
    ink-seen = "#403A4D"
    line = "#241F2E14"
    line-strong = "#241F2E26"
    wash = "#241F2E0a"
    press = "#241F2E14"
    accent = "#6A4FB0"
    accent-soft = "#6A4FB026"
    on-accent = "#FFFFFF"
    green = "#2F7D4A"
    plum = "#A3427E"
    red = "#B83A3A"
    grey = "#6E6780"
    warn = "#8F5A00"
    gold = "#B98900"

    """# + flatTables(done: "plum")

    static let brassSource = #"""
    # Brass: an ochre accent on a warm white panel, deep enough for text and
    # for white on a button. The rate limit's warning is a slate blue, so it
    # never reads as the accent.
    name = "Brass"
    version = 1
    description = "An ochre accent on a warm white panel; light."

    [light.palette]
    ground = "#F4F1E9"
    paper = "#FBF9F3"
    band = "#F0EBDE"
    lift = "#FFFFFF"
    ink = "#26221A"
    ink-2 = "#5A5345"
    ink-3 = "#736B5B"
    ink-seen = "#453F33"
    line = "#26221A14"
    line-strong = "#26221A26"
    wash = "#26221A0a"
    press = "#26221A14"
    accent = "#8A6100"
    accent-soft = "#8A610026"
    on-accent = "#FFFFFF"
    green = "#3B7A4B"
    violet = "#7A4FA0"
    red = "#B3392F"
    grey = "#736B5B"
    warn = "#3F6A99"
    gold = "#B98900"

    """# + flatTables(done: "violet")

    /// The tables the flat themes write, naming their palette's colours;
    /// `done` names the palette's colour for the done phase.
    private static func flatTables(done: String) -> String {
        #"""
        [surface]
        window = "ground"
        panel = "paper"
        header = "band"
        chrome = "band"
        raised = "lift"
        field = "wash"
        track = "press"

        [text]
        primary = "ink"
        secondary = "ink-2"
        tertiary = "ink-3"
        seen = "ink-seen"
        on-accent = "on-accent"

        [accent]
        accent = "accent"
        soft = "accent-soft"

        [line]
        separator = "line"
        border = "line-strong"

        [row]
        hover = "wash"
        pressed = "press"
        selected = "accent-soft"

        # Where each state is in its life: active is green, done purple,
        # failed red, and quiet grey.
        [phase]
        active = "green"
        done = "\#(done)"
        failed = "red"
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

        # The attention dot: the accent for a new or changed row; while a pull
        # request's checks fail, attention-failed, which is failed's colour unless set.
        [signal]
        attention = "accent"
        lease = "gold"

        [material]
        style = "flat"
        """#
    }
}
