# Notion's API

What shipyard's notes depend on (ADR 0009): how the app connects, the unique-ID number, the data-source query, page content as Markdown, rate limits and API versions. Shipyard sends `Notion-Version: 2025-09-03`.

Checked 2026-10-03 against:
- [Versioning](https://developers.notion.com/reference/versioning)
- [Upgrade guide 2025-09-03](https://developers.notion.com/docs/upgrade-guide-2025-09-03) and [upgrade guide 2026-03-11](https://developers.notion.com/docs/upgrade-guide-2026-03-11)
- [Internal connections](https://developers.notion.com/guides/get-started/internal-connections) and [Connection capabilities](https://developers.notion.com/reference/capabilities)
- [Data source properties](https://developers.notion.com/reference/property-object) (Unique ID, Multi-select)
- [Retrieve a data source](https://developers.notion.com/reference/retrieve-a-data-source) (checked 2026-10-04)
- [Query a data source](https://developers.notion.com/reference/query-a-data-source) and [Filter data source entries](https://developers.notion.com/reference/post-database-query-filter)
- [Working with markdown content](https://developers.notion.com/guides/data-apis/working-with-markdown-content)
- [Request limits](https://developers.notion.com/reference/request-limits) and [Status codes](https://developers.notion.com/reference/status-codes)
- [Search optimizations and limitations](https://developers.notion.com/reference/search-optimizations-and-limitations)
- [Pagination](https://developers.notion.com/reference/intro)

Measured the same day against the notes workspace with `ntn` 0.23.17, in throwaway databases since trashed, and through Claude's Notion connector.

## API versions

- Every request carries a `Notion-Version` header; it's required. A new version comes only with a backwards-incompatible change. New endpoints and fields arrive in every version, so the Markdown endpoints work on `2025-09-03` (measured: a page created with `markdown` on it).
- **`2025-09-03`** split databases from **data sources**. A database holds one or more data sources; the schema and the rows belong to a data source. `GET /v1/databases/{id}` returns the database's `data_sources` (`id`, `name`); querying, a page's parent and the schema all take a `data_source_id`. A database id and a data source id are not interchangeable.
- **`2026-03-11`**, the latest, renames `archived` to `in_trash` in every request and response, replaces `after` with `position` when appending blocks, and renames the `transcription` block to `meeting_notes`. Nothing else changed. `ntn` sends `2026-03-11` unless told otherwise (`--notion-version`, or `NOTION_API_VERSION`).
- On `2025-09-03`, `"archived": true` on a page **trashes** it. It isn't a note's archive: notes are archived by their `Status` property. Notion also has its own archive now, separate from the trash (a query's `is_archived` body parameter, `false` by default); shipyard doesn't use it.
- Notion has no plan to retire old versions, and promises notice if it does.

## Internal connections

- An **internal connection** belongs to one workspace and acts as its own bot user, not as a person. Its token is static: no OAuth flow, created in the Developer portal (Build → Internal connections) by a workspace owner, read from its Configuration tab.
- It sees nothing until a page is shared with it, from the portal's Content access tab or from the page's ••• → Connections. Sharing a page shares the pages and databases under it. Shipyard's connection is shared with the "Shipyard Notes" entry page only.
- **Capabilities** limit what it can call: read content, update content and insert content, independently. Shipyard's needs read (query) and insert (create a database, create a page). Creating a database without insert content is a 403.
- The token goes in `Authorization: Bearer <token>`. A bad token is 401 `unauthorized`; a page not shared with the connection is 404 `object_not_found`; missing capability is 403 `restricted_resource`.

## Databases and their properties

- `POST /v1/databases` (on `2025-09-03`) takes a `parent` page, a `title`, and `initial_data_source.properties`. It returns the database with its one data source's id in `data_sources`. Measured: a database under the entry page with `Name` (title), `No.` (`unique_id` with a prefix), `Labels` (`multi_select`, no options) and `Status` (`select`: Open, Archived).
- **Unique ID** (`unique_id`, shown as `auto_increment_id` by the connector): its `prefix` is a string or `null`. "Notion assigns each page a unique number within the data source. You can configure the prefix, but you cannot write a page's number." A page's value is `{"number": 42, "prefix": "TASK"}`. Measured: numbering starts at 1, and the spike saw that a trashed page's number is never given again. A data source has at most one unique ID property.
- **Multi-select:** option names are unique ignoring case, and can't contain commas; a request sets at most 100. Through the REST API (and so `ntn`), a page written with a new option name adds the option to the schema. Measured: Claude's Notion connector refuses it instead ("Invalid multi_select value … the data source must be updated to add it"), so an agent adds the option to the schema first.
- `GET /v1/data_sources/{id}` returns a data source's schema: `properties` by name, each with its `type` and that type's settings, so a `No.` reads `{"type": "unique_id", "unique_id": {"prefix": "SHOP"}}`. The app reads each database's prefix this way before it creates one, so a new database's prefix is unique.
- **Child databases:** `GET /v1/blocks/{page id}/children` lists a page's databases as `child_database` blocks, each with its `title`. That's how a project's database is found under the entry page by name.

## Querying a data source

- `POST /v1/data_sources/{data_source_id}/query` with an optional `filter`, `sorts`, `page_size` (at most 100, the default) and `start_cursor` from the last answer's `next_cursor`. Cursors are opaque. One query pages through at most 10,000 results.
- Without sorts, the order isn't guaranteed. Newest first is a sort on `No.` descending.
- Filters used for notes, measured:
  - by number: `{"property": "No.", "unique_id": {"equals": 7}}` (also `greater_than`, `less_than` and the rest),
  - by label: `{"property": "Labels", "multi_select": {"contains": "ideation"}}`,
  - open notes: `{"property": "Status", "select": {"does_not_equal": "Archived"}}`, which **also matches a page with no status**,
  - untidied: `{"property": "Name", "title": {"is_empty": true}}` or `{"property": "Labels", "multi_select": {"is_empty": true}}`,
  - combined in `{"and": [...]}` or `{"or": [...]}`.
- The connector's `notion-query-data-sources` filters the same way in `rows` mode (`auto_increment_id` with `number_equals`, `multi_select` with `enum_contains`, `select` with `enum_is_not`, which also keeps empty ones). Its `sql` mode has a shared workspace quota below the Business plan; `rows` mode worked on the free plan.
- **Search isn't for notes.** `POST /v1/search` matches titles, and its index lags: "Search indexing is not immediate". Notion's advice for "searching or filtering within a particular database" is the data source query. The connector's `notion-fetch` on a database returns its schema and data sources, not its rows.

## Pages and their content as Markdown

- `POST /v1/pages` with `parent: {"type": "data_source_id", "data_source_id": …}`, `properties`, and `markdown` for the body, which can't be combined with `children`. Measured on `2025-09-03`. Without a body the page is empty; the app's new-note icon sends only `Status` (Open), and its answer is the page, with its `url` and its new `No.`. Creating with `markdown` needs insert content (and, per the guide, insert property).
- Set the title explicitly. "If `properties.title` is omitted, the first `# h1` heading is extracted as the page title"; the spike saw a page created from only a heading end up untitled.
- `GET /v1/pages/{id}/markdown` returns `{"markdown", "truncated", "unknown_block_ids"}`; `PATCH /v1/pages/{id}/markdown` inserts or replaces content. `ntn pages get` and `ntn pages edit` use them (`edit` replaces the whole body).
- A page's `url` is its Notion link (`https://app.notion.com/p/<title>-<id>`), which opens it in the Notion app or the browser.
- A rich text's `text.content` is at most 2,000 characters; a request holds at most 1,000 blocks and 500 KB.

## Rate limits

- Per connection, "an average of three requests per second, with some bursts beyond the average allowed", and a per-workspace limit shared across its connections, scaled to the plan.
- Over either: 429 `rate_limited`, with `additional_data.rate_limit_reason`. Notion overloaded: 529 `service_overload`. Both carry `Retry-After` in whole seconds; wait at least that, then back off exponentially with jitter, within a retry limit.
- Retry 500, 502, 503 and 504 only for idempotent requests (GET, DELETE). Don't retry a 400; treat 401 and 403 as a broken or unauthorized token.
- Rate limits may change without a new version.
- Shipyard's refresh (one query per project with a database, every 60 seconds and when the menu opens) stays far below three per second for any likely number of projects, when the queries go one after another.

## `ntn`, Notion's CLI

- `ntn api <path>` calls any endpoint. The body comes from standard input (`ntn api v1/pages < body.json`), `-d '<json>'`, or inline `key=value` and `key:=<json>` arguments; `name==value` is a query parameter. Without a terminal, redirect standard input (`< /dev/null`) when the body doesn't come from it: `-d @file` with standard input left attached hangs.
- `ntn datasources query <data source or database id> --filter '<json>' --sort "No. desc"` prints one tab-separated row per page; `--json` prints the API's answer. `ntn datasources resolve <database id>` prints its data sources.
- `ntn pages get <id>` prints the page as Markdown with its properties as frontmatter; `ntn pages edit <id>` replaces the body from standard input, dropping that frontmatter. `ntn pages trash` needs `--yes` without a terminal.
- `ntn doctor` shows the logged-in workspace.
