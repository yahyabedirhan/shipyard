# shipyard notes

A **note** is the user's own note: an idea, a reminder, a "not now" thought, kept in Notion with one list per shipyard project and a number that only grows. The user dictates one to you, often by voice, and you write it into Notion: their words near verbatim, plus a title and labels. Later they point you at one ("use note 7 as the starting point").

Notion holds the notes and is their editor. Shipyard's menu lists each project's open notes, its notes count opens the project's database, and its new-note icon starts one; everything else (adding, finding, tidying, archiving) you do in Notion. The one `shipyard` command for notes is `shipyard notes check` (see Checking the structure).

## Where notes live

```text
Shipyard Notes               the user's home page: how to take and find notes, and the Projects index
├── Projects                 the parent of every notes database
│   ├── <project title>      one database per shipyard project
│   └── …
└── Agent guide              the rules and conventions for agents
```

These are the **fixed core**. The app reads them, so keep them exactly as written here:

- **The notes workspace:** a Notion workspace of the user's own, holding only notes.
- **The entry page:** "Shipyard Notes", at the top of that workspace. It's the user's home page; keep agents' rules off it.
- **The Projects page:** a child page of the entry page titled exactly "Projects". The app looks for databases only here.
- **One database per project,** directly under Projects, titled exactly the project's title: its `title` in the user's `config.toml`, else its `slug`. The app matches a project to its database by that title, so a database with another title, or one anywhere else, is invisible to it.
- **Its properties:**

| Property | Type | Holds |
|---|---|---|
| `Name` | title | the note's title |
| `No.` | unique ID, with the project's prefix | its number: Notion gives 1, 2, 3, … in each database, never twice, even after a trash. It can't be written |
| `Labels` | multi-select | its labels |
| `Status` | select: `Open`, `Archived` | whether it's live; empty means open |

The **Agent guide** page holds this workspace's conventions: label conventions, project prefixes, each database's icon and views, and kinds of sub-page. Read it before you write a note. To grow the structure, update the Agent guide first, then make the change. The entry page's **Projects index** (a table of project, prefix and database) lists every database; keep it current.

## Rules

- **Find notes with a query** on the project's data source, filtered by `No.`, `Labels` or `Status`. Search lags behind new pages, and fetching a database gives its schema and data source, without its notes.
- **Always set `Name`** when you create a note. A page created from only a heading can end up untitled.
- **Reuse labels.** Pick from the database's `Labels` options before inventing one, and follow the Agent guide's label conventions. Through the Notion connector or MCP, add a new option to `Labels` first: they refuse a value that isn't an option yet. `ntn` adds it by itself.
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

## Setting up ntn for the app

The menu and `shipyard notes check` read and write notes through `ntn`, with ntn's own login and its default workspace. The app keeps no Notion token, so there is nothing to paste into it. Notes are opt-in: the app runs no `ntn`, lists no notes and shows no notes banner or new-note icon until the user connects Notion in the app. When the user's notes don't list, check this first:

1. Install ntn: `curl -fsSL https://ntn.dev | bash` (Notion's installer, which puts it in `~/.local/bin`). The app also finds it in `/opt/homebrew/bin`, `/usr/local/bin` or on its `PATH`.
2. Log in from Terminal with `ntn login`, choosing the notes workspace.
3. Run `ntn doctor`: it shows the default workspace, which must be the notes workspace. Another workspace has no Shipyard Notes page, so the menu lists no notes.
4. Connect: in the panel's settings menu (the gear), **Set up Notion** opens the Notion view. It shows whether ntn is installed and logged in, and the name of ntn's workspace; **Check again** looks again after a change in Terminal. Once ntn is logged in, **Connect with ntn** lists the notes, and the app remembers it across restarts. The user presses it; `shipyard panel view notion` opens the view for them. **Set up Notion** has a check mark while Notion is connected and ntn works. **Disconnect** there stops the reads and takes the notes away.

Once connected, while ntn is missing or logged out the menu lists no notes, shows no error rows, hides the new-note icons, and its notes banner says what to do; with ntn's workspace holding no Shipyard Notes page, the banner says that instead. The app tries again every minute, so a fix shows without a restart.

## Finding a project's database

The project is the one the user names; otherwise the project in `config.toml` that watches the repository you're working in. On a machine without `config.toml`, the databases under Projects are titled with the projects' titles. Ask when none of these settles it.

- **Connector or MCP:** `notion-fetch` the entry page (find it once with `notion-search` for "Shipyard Notes"), then the Projects page it lists. The Projects page's content lists each database with its `data-source-url` (`collection://…`): pick the one titled the project's title (its `title` in `config.toml`, else its `slug`). Fetch that `collection://` URL for the schema and the current `Labels` options.
- **`ntn`:** find the entry page, the result whose parent is the workspace, then its Projects page, then that page's databases:

  ```sh
  ntn api v1/search query="Shipyard Notes" 'filter:={"property":"object","value":"page"}' < /dev/null
  ntn api v1/blocks/<entry page id>/children page_size==100 < /dev/null      # the child_page titled Projects
  ntn api v1/blocks/<Projects page id>/children page_size==100 < /dev/null   # child_database blocks, with titles
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

A project's database is created the first time a note is added to it, by you or by the menu's new-note icon. The icon creates the Projects page too when it's missing, and gives the database its icon, but it doesn't add views or touch the Projects index. When you find a database the index lacks, add its row and its views.

1. Pick a prefix: two to five uppercase letters from the project's title, the first four when they're free (`shipyard` → `SHIP`), not used by another database's `No.` (the Projects index lists them; each database's schema shows `unique_id` with its prefix).
2. Create the database under **Projects**, titled exactly the project's title, with the icon 🗂️:
   - Connector: `notion-create-database` with the Projects page as parent and `CREATE TABLE ("Name" TITLE, "No." UNIQUE_ID PREFIX 'SHIP', "Labels" MULTI_SELECT(), "Status" SELECT('Open':green, 'Archived':gray))`, then set its icon.
   - `ntn`: `ntn api v1/databases < database.json` with

     ```json
     {"parent": {"type": "page_id", "page_id": "<Projects page id>"},
      "title": [{"text": {"content": "<project title>"}}],
      "icon": {"type": "emoji", "emoji": "🗂️"},
      "initial_data_source": {"properties": {
        "Name": {"title": {}},
        "No.": {"unique_id": {"prefix": "SHIP"}},
        "Labels": {"multi_select": {"options": []}},
        "Status": {"select": {"options": [{"name": "Open", "color": "green"}, {"name": "Archived", "color": "gray"}]}}}}}
     ```

     Its answer carries the data source id, in `data_sources[0].id`.
3. Give it its two views, as the Agent guide describes. Only the connector (or MCP) can: rename the default view to **Open** with `notion-update-view` and `FILTER "Status" != "Archived"; SORT BY "No." DESC; SHOW "No.", "Name", "Labels", "Status"; QUICK FILTER "Labels"`, then `notion-create-view` an **Archived** table with `FILTER "Status" = "Archived"; SORT BY "No." DESC; SHOW "No.", "Name", "Labels", "Status"`. With only `ntn`, skip this step and say so.
4. Add its row (project, prefix, a mention of the database) to the Projects index on the entry page.

## Checking the structure

After you change the structure, and whenever the user says notes don't show in the menu, run `shipyard notes check` on the user's Mac. The app reads the workspace through `ntn`, the way the menu does, and prints one line per project (its prefix and open notes, or no database yet), then every problem. An error, such as a database outside Projects, a missing property or a page ntn can't see, hides notes from the menu; fix it, then run the check again. A warning, such as a database missing from the Projects index, is yours to tidy. It exits 1 on an error, 0 otherwise. Before the user connects Notion it runs no `ntn`: it exits 1 and says to press Connect with ntn in the Notion view. On a machine without the app, check the same layout through the connector or `ntn` by hand.
