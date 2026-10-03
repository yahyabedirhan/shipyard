# shipyard notes

A **note** is the user's own note: an idea, a reminder, a "not now" thought, kept in Notion with one list per shipyard project and a number that only grows. The user dictates one to you, often by voice, and you write it into Notion: their words near verbatim, plus a title and labels. Later they point you at one ("use note 7 as the starting point").

Notion holds the notes and is their editor. Shipyard's menu lists each project's open notes and its new-note icon starts one; everything else (adding, finding, tidying, archiving) you do in Notion. There's no `shipyard` command for notes.

## Where notes live

These are the **fixed core**. The app reads them, so keep them exactly as written here:

- **The notes workspace:** a Notion workspace of the user's own, holding only notes.
- **The entry page:** "Shipyard Notes", at the top of that workspace. Everything about notes hangs from it.
- **One database per project,** directly under the entry page, titled exactly the project's `name` in the user's `config.toml`. The app matches a project to its database by that title, so a database with another title is invisible to it.
- **Its properties:**

| Property | Type | Holds |
|---|---|---|
| `Name` | title | the note's title |
| `No.` | unique ID, with the project's prefix | its number: Notion gives 1, 2, 3, … in each database, never twice, even after a trash. It can't be written |
| `Labels` | multi-select | its labels |
| `Status` | select: `Open`, `Archived` | whether it's live; empty means open |

The entry page's **"How this is organized"** section holds the rules below and the parts of the structure that can grow: label conventions, views, kinds of sub-page, and each project's prefix. Read it before you write a note. To grow the structure (a new label convention, a view, a sub-page kind, a new project's prefix), update that section first, then make the change.

## Rules

- **Find notes with a query** on the project's data source, filtered by `No.`, `Labels` or `Status`. Search lags behind new pages, and fetching a database gives its schema and data source, without its notes.
- **Always set `Name`** when you create a note. A page created from only a heading can end up untitled.
- **Reuse labels.** Pick from the database's `Labels` options before inventing one, and follow the entry page's label conventions. Through the Notion connector or MCP, add a new option to `Labels` first: they refuse a value that isn't an option yet. `ntn` adds it by itself.
- **Archive by `Status`.** Set it to `Archived`, and back to `Open` to restore. Keep every note: trashing or deleting one loses it and its number for good.
- **Keep the user's words near verbatim.** Fix clear dictation slips and add paragraph breaks; the wording and meaning stay theirs. The title and labels are yours to write.
- **Say the number back.** After adding a note, tell the user its number with the prefix, such as `SHIP-7`.

## Reaching Notion

Use whichever route your harness has, in this order:

| Route | Where | How |
|---|---|---|
| The Notion connector | Claude on the web, desktop and phone, and Claude Code once the user connected Notion on claude.ai | its tools: `notion-fetch`, `notion-query-data-sources`, `notion-create-pages`, `notion-update-page`, `notion-update-data-source`, `notion-create-database` |
| Notion's hosted MCP | Codex, opencode and other MCP clients, at `https://mcp.notion.com/mcp` | the same tools as the connector |
| `ntn`, Notion's CLI | any shell where `ntn doctor` passes and names the notes workspace | `ntn datasources query`, `ntn pages get` and `edit`, `ntn api` for the rest |

When none reaches the notes workspace, tell the user and keep the note in your reply; don't write it anywhere else.

With `ntn`, pass a JSON body on standard input (`ntn api v1/pages < body.json`) or with `-d '<json>' < /dev/null`, or inline as `key:=<json>`. Redirect standard input on every call (`< /dev/null` when the body doesn't come from it): run without a terminal, `ntn` can otherwise wait on it for good.

## Finding a project's database

The project is the one the user names; otherwise the project in `config.toml` that watches the repository you're working in. On a machine without `config.toml`, the databases under the entry page are the projects' names. Ask when none of these settles it.

- **Connector or MCP:** `notion-fetch` the entry page (find it once with `notion-search` for "Shipyard Notes"). Its content lists each database with its `data-source-url` (`collection://…`): pick the one titled the project's name. Fetch that `collection://` URL for the schema and the current `Labels` options.
- **`ntn`:** find the entry page, the result whose parent is the workspace, then list its databases:

  ```sh
  ntn api v1/search query="Shipyard Notes" 'filter:={"property":"object","value":"page"}' < /dev/null
  ntn api v1/blocks/<entry page id>/children page_size==100 < /dev/null   # child_database blocks, with titles
  ```

  `ntn datasources query` takes the database id directly.

When the project has no database yet, create one (see Starting a project's notes).

## Working with notes

Each operation with the connector (or MCP), then with `ntn`. Query through the connector in `rows` mode: its `sql` mode has a plan quota. `<ds>` is the data source: the connector's `collection://` URL, or for `ntn` the data source id or the database id (`ntn datasources query` takes either). `ntn datasources query` prints one tab-separated row per note, its page id first, then its properties; add `--json` for the API's whole answer.

### Add a note

Connector: add any new label to `Labels` first (`notion-update-data-source`, `ALTER COLUMN "Labels" SET MULTI_SELECT(...)` listing every existing option too), then `notion-create-pages` with the data source as parent:

```json
{"parent": {"type": "data_source_id", "data_source_id": "<ds id>"},
 "pages": [{"properties": {"Name": "Group pings by agent", "Labels": "[\"ideation\"]", "Status": "Open"},
            "content": "What if pings were grouped by the agent that sent them?"}]}
```

`ntn`, with the body in a file:

```json
{"parent": {"type": "data_source_id", "data_source_id": "<data source id>"},
 "properties": {"Name": {"title": [{"text": {"content": "Group pings by agent"}}]},
                "Labels": {"multi_select": [{"name": "ideation"}]},
                "Status": {"select": {"name": "Open"}}},
 "markdown": "What if pings were grouped by the agent that sent them?"}
```

```sh
ntn api v1/pages < note.json
```

`ntn datasources resolve <database id>` prints the data source id. `ntn`'s answer is the new page: its `id`, and its number at `properties."No.".unique_id` (`{"number": 7, "prefix": "SHIP"}`). Through the connector, query the newest note to read its number.

### Find a note by its number

"Note 7" or `SHIP-7` is `No.` 7 in that project's database.

- Connector: `notion-query-data-sources` in `rows` mode, filter `{"type": "property", "property": "No.", "propertyType": "auto_increment_id", "operator": "number_equals", "value": {"type": "exact", "value": 7}}`. Then `notion-fetch` its URL for the body.
- `ntn`: `ntn datasources query <ds> --filter '{"property":"No.","unique_id":{"equals":7}}' < /dev/null`, then `ntn pages get <page id> < /dev/null` for the body.

### List open notes, by label

Open means `Status` isn't `Archived` (an empty status counts as open). Newest first is `No.` descending.

- Connector: `rows` mode with an `and` group of `{"property": "Labels", "propertyType": "multi_select", "operator": "enum_contains", "value": {"type": "exact", "value": "ideation"}}` and `{"property": "Status", "propertyType": "select", "operator": "enum_is_not", "value": {"type": "exact", "value": "Archived"}}` (each with `"type": "property"`), and `"sort": [{"property": "No.", "direction": "descending"}]`.
- `ntn`:

  ```sh
  ntn datasources query <ds> --sort "No. desc" \
    --filter '{"and":[{"property":"Labels","multi_select":{"contains":"ideation"}},{"property":"Status","select":{"does_not_equal":"Archived"}}]}' < /dev/null
  ```

Drop the `Labels` condition for every open note. Notes the user wrote straight into Notion may lack a title or labels: find them with `Name` or `Labels` `is_empty` (`{"or":[{"property":"Name","title":{"is_empty":true}},{"property":"Labels","multi_select":{"is_empty":true}}]}` with `ntn`), and tidy them.

### Edit a note

- Connector: `notion-update-page` with `update_properties` (`{"Name": "…", "Labels": "[\"ideation\"]"}`) for the title and labels, and `update_content` (an exact `old_str` and its `new_str`) for the body.
- `ntn`: properties with `ntn api v1/pages/<page id> -X PATCH 'properties:={"Name":{"title":[{"text":{"content":"…"}}]}}' < /dev/null`. The body with `ntn pages get <page id> < /dev/null > note.md`, your change to `note.md`, then `ntn pages edit <page id> < note.md`: `edit` replaces the whole body, and drops the frontmatter `get` adds.

### Archive or restore a note

- Connector: `notion-update-page`, `update_properties` with `{"Status": "Archived"}` (or `"Open"`).
- `ntn`: `ntn api v1/pages/<page id> -X PATCH 'properties:={"Status":{"select":{"name":"Archived"}}}' < /dev/null`.

## Starting a project's notes

A project's database is created the first time a note is added to it, by you or by the menu's new-note icon.

The icon makes the database with the same properties and a prefix no other database's `No.` uses, but it doesn't touch the entry page, so its prefix isn't in the list yet. When you find a database whose prefix the list lacks, add its line (`<project name>: <PREFIX>`) to the list.

1. Pick a prefix: two to five uppercase letters from the project's name (`shipyard` → `SHIP`), not already in the entry page's list of project prefixes (under "What can grow") nor used by another database's `No.` (its schema shows `unique_id` with the prefix).
2. Add the line `<project name>: <PREFIX>` to that list.
3. Create the database under the entry page, titled exactly the project's name:
   - Connector: `notion-create-database` with the entry page as parent and `CREATE TABLE ("Name" TITLE, "No." UNIQUE_ID PREFIX 'SHIP', "Labels" MULTI_SELECT(), "Status" SELECT('Open':green, 'Archived':gray))`.
   - `ntn`: `ntn api v1/databases < database.json` with

     ```json
     {"parent": {"type": "page_id", "page_id": "<entry page id>"},
      "title": [{"text": {"content": "<project name>"}}],
      "initial_data_source": {"properties": {
        "Name": {"title": {}},
        "No.": {"unique_id": {"prefix": "SHIP"}},
        "Labels": {"multi_select": {"options": []}},
        "Status": {"select": {"options": [{"name": "Open", "color": "green"}, {"name": "Archived", "color": "gray"}]}}}}}
     ```

   Its answer carries the data source id, in `data_sources[0].id`.
