# Hover help in a macOS menu bar panel

Checked 2026-09-26 for issue #72, against the sources listed at the end. The question: what should replace SwiftUI's `.help(...)` (macOS's native tooltips, "help tags") in shipyard's panel, a `MenuBarExtra` in `.window` style, 400 points wide, whose lists scroll inside it. Toolchain as checked: Swift 6.3 with Command Line Tools, macOS 26, deployment target macOS 14.

## Recommendation

**A small SwiftUI card that the panel draws itself (`hoverHelp(_:)` on a view, `hoverHelpHost()` once on the panel), placed by a pure, tested rule in the core. No package.**

- It looks like the panel: the system's `.regularMaterial`, the panel's hairline and corner radius, the panel's type scale. Its motion is the system spring the row highlight already uses, and an opacity fade. Nothing is hand-drawn beyond a rounded rectangle, and nothing is hand-animated.
- It meets each thing the ticket asks for. It never covers the row the pointer is on: it sits under the hovered view, or over it when there's no room below. The panel's edge can't cut it off, because it's placed inside the panel's bounds with a margin, and it's drawn at the panel's frame, so the scroll view's clip doesn't cut it either. It shows after a 0.5 s rest and at once while warm, as native tooltips do. It glides from row to row instead of lingering. It never takes the pointer, the keyboard focus or the key window.
- VoiceOver keeps the text: `.help` set the view's accessibility hint (Apple: "Adding help to a view configures the view's accessibility hint and its help tag"), so `hoverHelp(_:)` sets `.accessibilityHint` with the same words, and the card itself is hidden from accessibility.
- The style is chosen in one place (`HoverHelp.style`), and the placement rule is `HoverHelpPlacement` in `ShipyardCore/Menu/`, with tests.

**Runner-up: SwiftUI's own `.popover`, shown on hover.** It's the most native look (the system's popover chrome and arrow), and it's its own window, so it can sit beside the panel and cover no rows at all. It's built as `HoverHelp.Style.popover`, one line away. It isn't the default because the risks can only be checked in the real menu, which agents can't drive:

- An `NSPopover` is a window, and its behavior decides "which user interactions will cause the popover to close". A transient popover closes on most interactions. A popover that takes the key window could take the arrow keys from the list, which depends on the panel's window being key.
- Apple's guidance is to "show one popover at a time", and a hover popover per row means closing one popover and opening the next on every row the pointer crosses.
- The HIG places popovers for "a small amount of information or functionality" that people interact with, not for passive help. The HIG entry for passive help is the tooltip.

If the maintainer prefers the popover's look after trying both, switching is one line, followed by a check of the risks above.

## What the options were measured against

- Native SwiftUI over hand-rolled drawing or animation (the maintainer rejected a hand-rolled animation before), and no dated-looking native tooltip.
- Never covers the hovered row; never cut off at the panel's edge (a `MenuBarExtra` `.window` panel 400 pt wide, lists in a `ScrollView`).
- VoiceOver still gets the words.
- A package only if it clearly beats the native options: maintained, licensed, macOS 14 or earlier, and able to leave the scroll view's clip.

## Packages (Swift Package Manager)

Searched on GitHub (`tooltip swiftui`, `tooltip macos language:swift`, `popover language:swift macos`, by stars) on 2026-09-26. Every package that supports macOS and has more than a handful of stars:

| Package | Licence | Last release / tag | Last commit | macOS min | Stars | How it draws | Verdict |
|---|---|---|---|---|---|---|---|
| [quassum/SwiftUI-Tooltip](https://github.com/quassum/SwiftUI-Tooltip) | MIT | v1.4, 2023-05-10 | 2023-05-10 | 10.15 | 374 | `.overlay` on the view, `zIndex`, deprecated `.animation(_:)`, its own arrow shape; shown by a `Bool` binding, not on hover | Unmaintained for 3 years; an overlay on the row is clipped by the scroll view and the window like a hand-made one, with custom chrome |
| [jasudev/AxisTooltip](https://github.com/jasudev/AxisTooltip) | MIT | 0.5.0, 2022-03-02 | 2023-10-12 | 11 | 250 | `.overlay`; shown by an `isPresented` binding (a tap in its example) | Unmaintained; same clipping; README asks for `.branch("main")` |
| [chipjarred/CustomToolTip](https://github.com/chipjarred/CustomToolTip) | MIT | tag 1.0.3 (no release) | 2021-11-24 | 10.14 | 16 | AppKit: a borderless `CustomToolTipWindow` per tip, an `NSView` as content | Escapes the panel, but it's AppKit (`NSView.customToolTip`), not SwiftUI, and dormant for five years |
| [iSapozhnik/Popover](https://github.com/iSapozhnik/Popover) | MIT | 1.1.1, 2021-08-05 | 2021-08-05 | 10.11 | 130 | A custom status-bar popover window | For a status item's main window, not hover help; dormant |
| [MutatingFunc/Tooltips](https://github.com/MutatingFunc/Tooltips) | MIT | tag 1.1.0 (no release) | 2024-11-13 | 14 | 0 | "SwiftUI tooltips, stylised like macOS" | No users, no releases |

Others found are iOS-only (`oahhariri/SwiftyTooltip`, released 2026-09-23, `.iOS(.v15)` only; `DominikButz/DYPopoverView`, iOS 13) or unlicensed single-author snippets. **No package clearly beats the native options.** None is maintained and SwiftUI-native on macOS. The SwiftUI ones draw an overlay on the hovered view, which the panel's scroll view clips, and the one that escapes the panel is dormant AppKit.

Apple's **TipKit** (macOS 14+) has `popoverTip`, but it's for feature discovery, not hover help: "Use TipKit to show contextual tips that highlight new, interesting, or unused features people haven't discovered on their own yet … avoid displaying tips each time someone uses your app." Its rules and display frequency are the opposite of help on every hover.

## Native options

| Option | Look | Covers the hovered row? | Cut off at the panel's edge? | Focus, clicks | Verdict |
|---|---|---|---|---|---|
| `.help` (today) | The system's help tag: small, late, dated | Can cover the rows under it, and lingers | Can be (the ticket's screenshots) | None | What the maintainer wants gone |
| `.popover` on hover (SwiftUI, macOS 10.15+) | Native popover chrome and arrow | No: `arrowEdge` puts it beside the view; nil lets the system choose | No: its own window, repositioned by the system | A window: may take key and arrows; transient ones close on interaction | **Runner-up**, built as the alternative style |
| `NSPopover` through `NSViewRepresentable` | Same as above | No | No | Controllable (`behavior`, `animates`), but it's AppKit in a SwiftUI app | More control than `.popover` for the same risks, and more code |
| A SwiftUI card drawn by the panel (`overlayPreferenceValue`, anchor preferences) | The panel's own: system material, hairline | No, by placement | No, by placement inside the bounds | None: `allowsHitTesting(false)`, no window | **Recommended** |
| Text inline in the row | Plain text | n/a | n/a | None | Right where the text is short or the row can grow (note and error rows); the item rows can't hold their full detail on one line |
| No help | n/a | n/a | n/a | None | Right where the control is self-explanatory (chevrons, ✕, the copy icon, the lock) |

The facts behind the table:

- `help(_:)` "configures the view's accessibility hint and its help tag (also called a tooltip) in macOS" (macOS 11+). So dropping `.help` drops the hint unless the replacement sets `accessibilityHint(_:)` (macOS 13+, "Communicates to the user what happens after performing the view's action").
- `popover(isPresented:attachmentAnchor:arrowEdge:content:)`: "arrowEdge: The edge of the attachmentAnchor that defines the location of the popover's arrow. The default is nil, which results in the system allowing any arrow edge". The anchor defaults to `.rect(.bounds)`.
- `NSPopover`: "The system automatically positions each popover relative to its positioning view"; `show(relativeTo:of:preferredEdge:)` takes "the edge of positioningView the popover should prefer to be anchored to", and "if the popover is already being shown, this method updates the anchored view, rectangle, and preferred edge". Behaviors: "A transient popover is closed in response to most user interactions, whereas a semi-transient popover is closed when the user interacts with the window containing the popover's positioning view."
- `NSVisualEffectView.Material.toolTip` exists ("the material for the background of a tool tip"), so AppKit has a tooltip material. SwiftUI's `.regularMaterial` is the SwiftUI-native equivalent the card uses.
- `onHover(perform:)` (macOS 10.15+) "adds an action to perform when the user moves the pointer over or away from the view's frame". Shipyard's rows already use it, and anchor preferences, for the row highlight.
- HIG, Offering help: tooltips should "describe only the control that people indicate interest in", "avoid repeating a control's name in its tooltip", be "60 to 75 characters" at most, and use sentence case. It also suggests "an inline view that succinctly describes the task" for simple tasks.
- HIG, Popovers: "Ideally, a popover doesn't cover the element that revealed it"; "Show one popover at a time"; "Use a popover to expose a small amount of information or functionality".

## How menu bar apps show hover help

Read in each app's source on 2026-09-26:

- **Maccy** ([p0deje/Maccy](https://github.com/p0deje/Maccy), 2.7.1, 2026-08-10), a SwiftUI clipboard manager in a menu bar panel, uses native `.help` for its list items and toolbar buttons (`ListItemView.swift`, `ToolbarView.swift`, whose `KeyboardShortcutHelpModifier` "use[s] the same localized description for visual help and the accessibility label"). Richer content (an item's full preview) goes in a slide-out beside the list (`SlideoutContentView.swift`), not in a tooltip.
- **Stats** ([exelban/stats](https://github.com/exelban/stats), v3.0.17, 2026-09-20), AppKit, sets native `toolTip` throughout its popups (33 files).
- **CodexBar** ([steipete/CodexBar](https://github.com/steipete/CodexBar), v0.67.0, 2026-09-26) uses native `.help` (18 files) and `toolTip` in its `NSMenu` rows. It has no `NSPopover`.
- **Ice** ([jordanbaird/Ice](https://github.com/jordanbaird/Ice), 0.11.12, 2024-10-29) uses native `.help` in its settings.

None of them ships a custom tooltip. They use native help tags and move the long content into the layout (Maccy's slide-out). So shipyard's card is a step past what these apps do. It keeps their idea of short help on hover, with long text in the layout (the note and error rows now wrap), and makes the help itself look like the panel.

## Each call site

The 14 `.help(` sites in `Sources/ShipyardApp`, and what each became:

| Site | Now | Why |
|---|---|---|
| Row (`itemRow`, both layouts) | Card: `PanelText.rowHelp`, lined up with the title | The full detail doesn't fit the row. The first line is primary, the checks and ⌥-click lines are quieter |
| Check dot (`CheckDot`) | No hover help; its words moved into the row's help ("Checks failed") | A help source nested inside the row's would compete with it; VoiceOver keeps the dot's label |
| Layout button | Card: `PanelText.layoutButton` | Says the current layout and what a click does |
| Refresh | Card: `PanelText.refreshHelp`, "Refresh (⌘R)" | An icon-only button; the help names the shortcut |
| Settings gear | Card: `PanelText.settings`; now also its VoiceOver label | An icon-only menu |
| Account button | Card: `PanelText.profileHelp` | Gives the full name and what a click does |
| Tab pill | Card with the title, only while the title is cut off | HIG: don't repeat a control's name; it's only useful when truncated |
| Subheader (`GroupHeader`) | No hover help; `accessibilityHint(PanelText.groupFoldHelp)` | The chevron says it folds |
| List section header | No hover help; `accessibilityHint(PanelText.sectionFoldHelp)` | The chevron says it collapses |
| Note row | Inline: the note wraps | Short sentences; a row can grow |
| Error row | Inline: wraps up to 3 lines, selectable | An error is worth reading in full, without a hover |
| Command box's Copy | No hover help | The icon turns into a checkmark; the VoiceOver label stays |
| Skill card's Close | No hover help | An ✕ in a card's corner; the VoiceOver label stays |
| Picker's lock | No hover help; VoiceOver label "Private" | The lock says private |

## Sources

- Apple, [help(_:)](https://developer.apple.com/documentation/swiftui/view/help(_:)-6oiyb) (macOS 11+), [accessibilityHint(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:)) (macOS 13+), [onHover(perform:)](https://developer.apple.com/documentation/swiftui/view/onhover(perform:)) (macOS 10.15+), [popover(isPresented:attachmentAnchor:arrowEdge:content:)](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)) (macOS 10.15+): checked 2026-09-26.
- Apple, [NSPopover](https://developer.apple.com/documentation/appkit/nspopover), [show(relativeTo:of:preferredEdge:)](https://developer.apple.com/documentation/appkit/nspopover/show(relativeto:of:preferrededge:)), [behavior](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.property), [NSVisualEffectView.Material.toolTip](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/tooltip): checked 2026-09-26.
- Apple, [TipKit](https://developer.apple.com/documentation/tipkit) (macOS 14+): checked 2026-09-26.
- Apple Human Interface Guidelines, [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) (tips; macOS tooltips) and [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers): checked 2026-09-26.
- GitHub repositories, read through the GitHub API on 2026-09-26 (README, `Package.swift`, releases and tags, last commit on the default branch): [quassum/SwiftUI-Tooltip](https://github.com/quassum/SwiftUI-Tooltip) (`Sources/SwiftUITooltip/TooltipModifier.swift`), [jasudev/AxisTooltip](https://github.com/jasudev/AxisTooltip) (`Sources/AxisTooltip/AxisTooltip.swift`), [chipjarred/CustomToolTip](https://github.com/chipjarred/CustomToolTip) (`CustomToolTipWindow.swift`), [iSapozhnik/Popover](https://github.com/iSapozhnik/Popover), [MutatingFunc/Tooltips](https://github.com/MutatingFunc/Tooltips), [oahhariri/SwiftyTooltip](https://github.com/oahhariri/SwiftyTooltip), [DominikButz/DYPopoverView](https://github.com/DominikButz/DYPopoverView).
- Menu bar apps' source, read on 2026-09-26: [p0deje/Maccy](https://github.com/p0deje/Maccy) (`Maccy/Views/ListItemView.swift`, `ToolbarView.swift`, `SlideoutContentView.swift`), [exelban/stats](https://github.com/exelban/stats), [steipete/CodexBar](https://github.com/steipete/CodexBar), [jordanbaird/Ice](https://github.com/jordanbaird/Ice); latest releases from each repository's releases page.
