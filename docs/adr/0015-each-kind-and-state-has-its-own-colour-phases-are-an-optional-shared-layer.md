# Each kind and state has its own colour, phases are an optional shared layer

A theme (ADR 0014) used to colour pull requests, issues and runs through five tokens, `state.open`, `state.draft`, `state.merged`, `state.closed` and `state.running`.
The app decided which token each state took: a succeeded run and a closed issue drew `state.merged`, and a failed run drew `state.closed`.
So a theme author could not give a succeeded run a colour of its own, and the rule that connects a state to its colour lived in Swift, out of the theme's reach.

**Each kind and state has its own colour.**
A theme sets the **state colour** of each state of each kind in a `[states.<kind>]` table: `[states.pull-request]` (`open`, `draft`, `merged`, `closed`), `[states.issue]` (`open`, `closed`) and `[states.run]` (`running`, `succeeded`, `failed`).
The theme reader gives one lookup, a kind, a state and an appearance in and a colour out, and the panel's state icons use it alone.
The app keeps no mapping from a state to a colour.

**Phases are an optional shared layer.**
A **phase** is where a state is in its life: `active`, `done`, `failed` or `quiet`.
An optional `[phase]` table names one colour per phase, and a state's value may name a phase, so one red serves every failed state.
A state no theme sets takes its phase, and a phase no theme sets is its macOS colour: active green, done purple, failed red, quiet grey.
So a theme with neither table draws the lifecycle rule in system colours, and a theme that sets only `[phase]` recolours every kind at once.

**A state colour resolves like a token.**
The appearance's table, then the table without a prefix, then the `extends` chain, then the default.
A state value is a phase name, a palette name, a hex colour or `system`; a phase value is a palette name, a hex colour or `system`, and never another phase.

## Considered Options

- **Keep the `state.*` tokens and the mapping in Swift.** No change for theme authors, but a succeeded run could never differ from a merged pull request, and the lifecycle rule stayed in code.
- **Phases alone.** One colour per phase is short to write, but a kind could not differ from another in one phase, such as a closed issue from a merged pull request.
- **States alone.** Every colour is explicit, but a theme repeats one red for every failed state and drifts when one copy changes.
- **States, with phases as an optional shared layer (chosen).** A theme names shared colours once and still gives one state its own.

## Consequences

- The tokens `state.open`, `state.draft`, `state.merged`, `state.closed` and `state.running` are removed, with no old form kept before the public launch.
  A theme file that uses one gets a problem on its line that names the keys that replace it.
- `state.success`, `state.failure`, `state.pending` and `state.neutral` stay tokens for checks, reviews, the rate limit, pings and notes.
- The six built-in themes write `[phase]` and `[states.*]`, and draw every state in the colour it had before.
- The contrast check still measures text alone: state colours are icons, not text.
