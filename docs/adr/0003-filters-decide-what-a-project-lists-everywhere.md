# A project's filters decide what it lists, and only listed items are counted and notified

Each item kind of a project has filters: `states`, the closed or finished window, `drafts`, `authors` (`show` minus `hide`), and for pull requests `review-requested`. They combine with AND into the project's **listing**. The listing is the only thing the menu shows, the attention counts count (in the header, the tabs and the menu bar) and the notifications fire for. A notification rule's own `authors` can only narrow the listing further. It can't reach an item the listing leaves out. Every fetched item is still recorded as known, listed or not, so an item that a later filter change brings into view doesn't notify as though it were new.

We chose this because shipyard is used two opposite ways. For the maintainer, it shows what they and their agents open. For contributors' maintainers, as in ghbar, it shows only what other people send. A notification or a count for an item the menu doesn't show would open something the user can't find. One rule in one place (the listing) also keeps the filters maintainable as more are added: a new filter is one more field and one more check, not a special case in each consumer.

## Considered options

- **Filters for the menu only, with notifications keeping their own rules**, as `hide-authors` and notification rules were separate before: rejected, for the mismatch above and for the duplicate checks it needs.
- **A filter expression language** (`"others and not bots"`): rejected. It's hard for agents to write correctly and hard to validate, and independent fields combined with AND cover every case asked for.
