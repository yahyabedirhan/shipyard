# Site: low-level design

This document is the module design of shipyard's website, the static site at `https://shipyard.yahyapak.dev` built from `site/`.
It explains the code as it is: what the site must do, which modules exist, what state and rules each one owns, how they call each other and where each file sits.
The app and the `shipyard` command have their own design in `docs/low-level-design.md`, and this document leaves them out.

It follows the low-level design delivery framework, so each kind of answer has one place:

1. **Requirements:** the capabilities, the rules, the error handling and the scope.
2. **Entities and relationships:** the pages, the content sources, the analytics and the build parts, and how they connect.
3. **Class design:** the folder tree, each module's state and API, and where each rule lives.
4. **Implementation:** traced flows as call trees, with the owning file beside each call.
5. **Extensibility:** the likely changes, and what each one touches.

Requirements read from the code and the tests are marked **inferred**.
What the code can't show is marked as a Gap with its source.
Weaknesses are listed as observations in `Class design` > 'Observations', without changes.

---

## Overview

### The site in one paragraph

The site is an Astro project with its own `package.json`, rendered to static HTML at build time and served by a Cloudflare Worker's static assets.
It has four pages: the landing page at `/`, the user-facing documentation at `/docs`, the privacy page at `/privacy` and a 404 page.
Each page reads with JavaScript off; only the parts that move hydrate in the browser, as React islands.
The documentation's configuration and command references are generated at build time from the repository one folder up: the JSON schemas, the agent skill, the Swift command table and `CHANGELOG.md` (`site/plugins/repo.ts`).
The same content is also written out as plain text for AI agents: `llms.txt`, `llms-full.txt` and one Markdown file per documentation section under `/docs/` (`site/plugins/agents.ts`).
Analytics (PostHog) and error reports (Sentry) are built in only when their keys are set, load lazily, and honour an opt-out kept in the browser (`site/src/analytics.ts`, `site/src/errors.ts`, `site/src/consent.ts`).

### Running, building, testing and deploying

All commands run from `site/` (`site/package.json` > `scripts`).

| Command | What it does |
|---|---|
| `npm ci` | Installs the locked dependencies. Node 22 or later (`engines`). |
| `npm run dev` | Serves the site at `http://localhost:4321/`, with the generated files and the screenshots served from memory, and a full reload when a repository source changes (`site/plugins/site.ts`). |
| `npm test` | Runs Vitest over `src/**/*.test.*`, `plugins/`, `scripts/` and `worker/` through Astro's Vite config (`site/vitest.config.ts`). |
| `npm run build` | `astro check`, then `astro build` into `site/dist/`, then `scripts/check-public-bundle.mjs`. |
| `npm run deploy` | Builds, then `wrangler deploy` to the `shipyard-site` Worker (`site/wrangler.jsonc`). |
| `npm run social` | Redraws the Open Graph cards in `public/og/`, the favicons and the GitHub social preview (`site/scripts/social.mjs`). |
| `npm run terminal` | Redraws `cli-help-dark.png` from the installed command's `--help` (`site/scripts/terminal.mjs`). |

A build with analytics reads `VITE_POSTHOG_KEY`, `VITE_POSTHOG_HOST` and `VITE_SENTRY_DSN` from the shell or `site/.env.local` (`site/.env.example`).
Without them the build has no analytics and no error reporting, and the bundle check proves that neither client is in it.

The `site` workflow (`.github/workflows/site.yml`) runs `npm ci`, `npm test` and `npm run build` when `site/` or a repository file the site is made from changes.
It doesn't deploy.
Cloudflare Workers Builds deploys the site: on every push to `main` it runs `npm run build` and `npx wrangler deploy` in `site/`, with the three keys as the trigger's build variables.
It picks Node from `engines` in `site/package.json`.
`npm run deploy` from a `main` checkout still deploys by hand, with the keys in `site/.env.local`.

### Where each page's code lives

| URL | Route file | Page code | Islands |
|---|---|---|---|
| `/` | `src/pages/index.astro` | `src/landing/` | `CodeTabs`, `CodeBlock` from `src/guide/CodeBlocks.tsx` |
| `/docs` | `src/pages/docs.astro` | `src/guide/` | `NavSections`, `JumpMenu`, `Install`, `CodeTabs`, `CodeBlock`, `ConfigExplorer` |
| `/privacy` | `src/pages/privacy.astro` | `src/privacy/`, `site/PRIVACY.md` | `OptOut` |
| `/404` | `src/pages/404.astro` | `src/privacy/Plain.astro` | none |
| `/llms.txt`, `/llms-full.txt`, `/docs/<section>.md` | none | `plugins/agents.ts` | none |
| `/sitemap.xml` | none | `plugins/site.ts` | none |

Every page is wrapped in `src/layouts/Base.astro`, which writes the head from `src/meta.ts` and starts `src/boot.ts`.

### Where to start reading

1. `site/astro.config.ts`: the build's shape in twenty lines.
2. `site/plugins/site.ts`: what the build adds beside the pages.
3. `site/src/pages/docs.astro`, then `site/src/guide/Guide.astro` and `site/src/guide/Section.astro`: how the documentation page is put together.
4. `site/src/guide/content.ts`: the documentation's words, one entry per section.
5. `site/src/boot.ts`, then `site/src/analytics.ts`: what runs in the browser.

---

## 1. Requirements

### Capabilities

1. Serve a landing page that says what shipyard is, who it is for and how it is used, with the install lines and the real panel (`src/landing/Landing.astro`, `src/landing/landing.test.ts`).
2. Serve one documentation page of numbered sections in five groups, with a nav that marks the section being read, margin notes, diagrams, screenshots, copyable code and a config explorer (`src/guide/`).
3. Generate the configuration reference from `schema/config.schema.json` and `schema/cli.schema.json`, filling missing descriptions from the skill's key table (`plugins/repo.ts` > `referenceData`, `src/reference/parse.ts`).
4. Generate the command reference from the Swift sources that define the command table (`plugins/repo.ts` > `commandSources`, `src/reference/parse.ts` > `commandReference`).
5. Show the three presets from `skills/shipyard/presets.md`, the ping and notice flags from the skill, the app version from `Version.swift` and the latest release from `CHANGELOG.md` (`plugins/repo.ts`).
6. Publish the documentation as plain text for agents: `llms.txt`, `llms-full.txt` and `/docs/<section>.md` (`plugins/agents.ts`).
7. Serve the privacy page from `site/PRIVACY.md` with buttons to opt out (`src/pages/privacy.astro`, `src/privacy/OptOut.tsx`).
8. Answer an unknown path with a real 404: the 404 page for a browser, plain text pointing to `llms.txt` otherwise (`worker/index.js`).
9. Give each page a full head: title, description, canonical address, social card and robots (`src/meta.ts`, `src/layouts/Base.astro`).
10. Move between pages without a full load, and count those moves as page views (`src/layouts/Base.astro` > `ClientRouter`, `src/boot.ts`).
11. Count page views, a fixed set of custom events and outbound clicks, cookieless, and report errors, when the build has the keys (`src/analytics.ts`, `src/errors.ts`).
12. Tell agents from people in analytics, and let an agent name itself from fixed lists (`src/actor.ts`).
13. Draw the social cards, favicons and the command's help screenshot from the site's own words and colours (`scripts/`).

### Rules and completion

- Every page is whole HTML that reads with JavaScript off (`scripts/check-public-bundle.mjs` > `pages`).
- An island takes plain data as props, never a function, so it never loads the documentation's content (`src/guide/CodeBlocks.tsx`, `src/guide/DocsNav.tsx`).
- A build without `VITE_POSTHOG_KEY` holds no PostHog code, and a build without `VITE_SENTRY_DSN` holds no Sentry code (`scripts/check-public-bundle.mjs`).
- With a key, each client loads lazily, after the page is idle, in a chunk no page loads up front (`src/analytics.ts` > `startAnalytics`, `src/errors.ts` > `startErrorReporting`, `scripts/check-public-bundle.mjs`).
- Consent has three levels: `all`, `pageviews` and `none` (`src/consent.ts`).
  `pageviews` sends page views and page leaves only; `none` loads neither client.
  Any level other than `all` deletes the visitor id and the tab's agent identity.
- Events carry only fixed, typed properties, never free text or a copied text or a link's address (`src/analytics.ts` > `AnalyticsEvents`).
- `PRIVACY.md` lists every event name (`src/consent.test.ts` > 'PRIVACY.md lists every event').
- An agent's name and purpose come only from fixed lists; anything else is ignored and still removed from the address bar (`src/actor.ts`, `src/actor.test.ts`).
- A WebDriver browser counts as an agent (`src/actor.ts` > `resolveActor`).
- One page sends at most 10 error reports (`src/errors.ts` > `MAX_EVENTS`, `src/sentry.ts`).
- Every key in `config.schema.json` and `cli.schema.json` appears on the page and in `docs/configuration.md`, and the skill names no key the schema lacks (`src/reference/reference.test.ts`). **inferred** as a rule from the tests.
- Every command the Swift sources declare appears on the page and in `docs/commands.md` (`src/reference/reference.test.ts`). **inferred**
- Every screenshot id a page uses is in `shots.json`, and each entry has its capture steps, its saved file and where it is used (`src/site.test.ts` > 'screenshots'). **inferred**
- Every colour and size lives in `src/tokens.css`; other stylesheets only read its variables (`src/site.test.ts` > 'keeps every colour and size in tokens.css').
- Titles stay between 50 and 65 characters and descriptions between 110 and 160, and every social card is 1200 by 630 (`src/site.test.ts` > 'page heads'). **inferred** from the tests; `src/meta.ts` states the targets as "near 60" and "near 155".
- The site's files hold no private paths, machine labels or em dashes in prose (`src/site.test.ts` > 'what the site never holds').
- The 404 page is `noindex` and stays out of the sitemap (`src/meta.ts` > `listed`, `src/site.test.ts`).
- The site's copy follows `docs/messaging.md`; `src/messaging.ts` changes only to match it (`src/messaging.ts`).
- Hashed files under `/_astro/` are cached for a year; HTML and unhashed files are checked on every visit (`public/_headers`).

### Error handling

- A missing screenshot id throws while the page renders, so the build fails (`src/guide/figures.tsx` > `Shot`).
- A built page missing its required words, a missing required file, or an analytics client without its key fails the bundle check with exit code 1 (`scripts/check-public-bundle.mjs`).
- Blocked storage never breaks a page: consent, the visitor id and the agent identity then last for that page only (`src/consent.ts`, `src/visitor.ts`, `src/actor.ts`).
- Analytics and error reporting never throw into the page: tracker calls are wrapped, the event queue is capped at 50, a failed client load drops the queue, and a reporter's throw is swallowed (`src/analytics.ts` > `createTracker`, `src/errors.ts` > `createErrorQueue`).
- Do Not Track keeps PostHog from loading (`src/analytics.ts` > `doNotTrack`).
- A blocked clipboard still shows the copy button's check (`src/guide/CodeBlocks.tsx` > `CopyButton`).
- An unknown path gets a 404 status in both forms; when the 404 page can't be fetched, a browser gets the plain-text 404 (`worker/index.js`).
- The scripts that draw images stop with the HTTP status when Google Fonts fails (`scripts/render.mjs` > `fonts`).

### Scope

In:

- The four pages, the agent files, the sitemap and the copied screenshots.
- The generated configuration and command references.
- The site's analytics, consent and error reporting.
- The Worker that answers unknown paths, and the static headers.
- The scripts that draw the social cards, favicons and the help screenshot.

Out:

- The app, the `shipyard` command and the agent skill: the site only reads their files (`docs/low-level-design.md`).
- Capturing the panel screenshots: the app does that, following each `shots.json` entry's `capture` steps on the Mac (`site/shots.json` > `about`).
- The messaging itself: `docs/messaging.md` owns the words that `src/messaging.ts` quotes.
- Server-side code beyond the 404 Worker: the site is static (`astro.config.ts` > `output: 'static'`).
- A light theme: `src/tokens.css` holds one dark theme, and every page sets `color-scheme: dark` (`src/guide/docs.css`).

---

## 2. Entities and relationships

### Entities

Pages and their parts:

- **Page route**: one file in `src/pages/`, which names its `PageMeta` and its page component.
- **Page meta**: one page's path, built file, title, description, social card and listing (`src/meta.ts` > `PAGES`).
- **Layout**: the document every page shares, with the head, fonts, client router and the browser start-up (`src/layouts/Base.astro`).
- **Landing page**: `src/landing/Landing.astro` and its words in `src/landing/copy.ts`.
- **Guide**: the documentation page's code, `src/guide/`, with `Guide.astro` as its entry.
- **Doc section**: one numbered section of the documentation, as data (`src/guide/content.ts` > `DocSection`).
- **Plain page**: the wordmark, one column and a footer, shared by the privacy and 404 pages (`src/privacy/Plain.astro`).
- **Island**: a React component that renders at build time and hydrates in the browser.

Content sources:

- **Messaging**: the name, the one line, the links and the install lines (`src/messaging.ts`).
- **Guide content**: the sections, groups, limits, questions and install ways (`src/guide/content.ts`).
- **Reference data**: the configuration keys, command table, presets, flags, version and latest release, made from repository files (`plugins/repo.ts` > `referenceData`, served as `virtual:shipyard-reference`).
- **Privacy text**: `site/PRIVACY.md`, served as HTML through `virtual:shipyard-privacy`.
- **Shot**: one screenshot's entry in `site/shots.json`; its PNG lives in `assets/screenshots/launch/`.
- **Explorer model**: the made-up items and snippets the config explorer applies (`src/guide/explorer.ts`).
- **Tokens**: every colour, face, size and space (`src/tokens.css`).

In the browser:

- **Boot**: the start-up that runs once per full page load (`src/boot.ts`).
- **Tracker**: the PostHog queue and its lazy client (`src/analytics.ts`, `src/posthog.ts`).
- **Error queue**: the Sentry queue and its lazy client (`src/errors.ts`, `src/sentry.ts`).
- **Consent**: the visitor's analytics level (`src/consent.ts`).
- **Actor**: who an event comes from, a person with a visitor id or an agent (`src/actor.ts`, `src/visitor.ts`).
- **Device facts**: the coarse super properties (`src/device.ts`).

Build and serving:

- **Site integration**: the Astro integration that serves the virtual modules and writes the extra files (`plugins/site.ts`).
- **Repository reader**: the only module that reads the repository's files (`plugins/repo.ts`).
- **Agent files**: the plain-text documentation (`plugins/agents.ts`).
- **Bundle check**: the post-build gate (`scripts/check-public-bundle.mjs`).
- **Worker**: the 404 answer (`worker/index.js`), configured by `wrangler.jsonc`.

A page's `title`, a section's `nav` and a shot's `shows` are fields, not entities.

### Relationships

```text
astro.config.ts -> plugins/site.ts (siteIntegration)        build orchestrator
astro.config.ts -> plugins/repo.ts (appVersion)             __APP_VERSION__
plugins/site.ts -> plugins/repo.ts (referenceData)          virtual:shipyard-reference
plugins/site.ts -> site/PRIVACY.md -> reference/markdown    virtual:shipyard-privacy
plugins/site.ts -> plugins/agents.ts                        llms.txt, llms-full.txt, docs/*.md
plugins/site.ts -> meta.ts (PAGES)                          sitemap.xml
plugins/site.ts -> shots.json + assets/screenshots/launch   dist/shots/*.png
plugins/repo.ts -> reference/parse.ts                       text -> data
plugins/agents.ts -> guide/content.ts, messaging.ts, reference/markdown.ts

pages/*.astro -> layouts/Base.astro -> meta.ts, tokens.css, boot.ts
pages/index.astro   -> landing/Landing.astro -> guide/CodeBlocks, guide/figures, guide/docs.css
pages/docs.astro    -> guide/Guide.astro -> guide/Section.astro -> guide/{content, parts, diagrams, figures, CodeBlocks, Install, ConfigExplorer}
pages/privacy.astro -> privacy/Plain.astro, privacy/OptOut.tsx, virtual:shipyard-privacy
pages/404.astro     -> privacy/Plain.astro
guide/*, landing/*  -> messaging.ts
guide/parts, guide/Section -> reference/data.ts -> virtual:shipyard-reference
guide/figures -> shots.json

boot.ts -> analytics.ts -> consent.ts, actor.ts, visitor.ts, device.ts
analytics.ts ..lazy..> posthog.ts -> posthog-js (slim)
boot.ts -> errors.ts -> consent.ts
errors.ts ..lazy..> sentry.ts -> @sentry/browser
islands (CodeBlocks, Install, ConfigExplorer, OptOut) -> analytics.ts (track, optOut)
consent.ts -> visitor.ts (forgetVisitor), actor.ts (forgetAgent)

Cloudflare assets (dist/, _headers) -> worker/index.js   only for unmatched paths
```

### Rule owners

| Rule | Owner |
|---|---|
| Which pages exist, their heads and whether search lists them | `src/meta.ts` |
| What the documentation says, section by section | `src/guide/content.ts` |
| Which configuration keys and commands exist | the repository's schemas and Swift sources, read by `plugins/repo.ts` and parsed by `src/reference/parse.ts` |
| Which screenshots exist and how each is taken | `site/shots.json` |
| What the consent level is | `src/consent.ts` |
| Whether an event is sent | `src/analytics.ts` > `track` (key and consent) |
| Whether a visitor is a person or an agent | `src/actor.ts` > `resolveActor` |
| Whether a build is fit to publish | `scripts/check-public-bundle.mjs` |
| What an unknown path answers | `worker/index.js` |
| What a file's cache and content type are | `public/_headers` |

---

## 3. Class design

### Folder tree

```text
site/
├── package.json                  the site's own Node project: scripts and dependencies
├── astro.config.ts               static output, file-format pages, React, the site integration, __APP_VERSION__
├── tsconfig.json                 strict TypeScript for src/, plugins/ and the configs
├── vitest.config.ts              Vitest through Astro's Vite config, so tests see the virtual modules
├── wrangler.jsonc                the Cloudflare Worker: dist/ as assets, worker/index.js for unmatched paths, the custom domain
├── shots.json                    every screenshot: what it shows, its demo config, capture steps, file and where it is used
├── PRIVACY.md                    the privacy page's text, also the source the event-list test checks
├── .env.example                  the analytics keys a build reads; the real ones are never committed
├── docs/
│   └── low-level-design.md       this document
├── plugins/
│   ├── site.ts                   the Astro integration: virtual modules, dev middleware and watcher, files written after the build
│   ├── repo.ts                   the only reader of the repository: schemas, skill, presets, changelog, Swift command files, version
│   └── agents.ts                 llms.txt, llms-full.txt and one Markdown file per documentation section
├── scripts/
│   ├── check-public-bundle.mjs   the post-build gate: page words, required files, analytics clients, JavaScript sizes
│   ├── render.mjs                shared by the image scripts: fonts from Google Fonts, SVG to PNG, word wrapping
│   ├── social.mjs                the Open Graph cards, the GitHub social preview and the favicons
│   └── terminal.mjs              the help screenshot, drawn from the installed command's --help
├── public/                       copied into dist/ as they are
│   ├── _headers                  cache and content-type rules per path
│   ├── robots.txt                every crawler welcome, with the sitemap and llms.txt
│   ├── og/{home,docs,privacy}.png  social cards, drawn by npm run social
│   └── favicon.png, apple-touch-icon.png, logo.png
├── worker/
│   ├── index.js                  the 404 answer for paths that match no file
│   └── index.test.mjs            the Worker's two answers
└── src/
    ├── pages/                    one route per page; each names its PageMeta and page component
    │   ├── index.astro           / -> landing/Landing.astro
    │   ├── docs.astro            /docs -> guide/Guide.astro
    │   ├── privacy.astro         /privacy -> PRIVACY.md as HTML and the OptOut island
    │   └── 404.astro             the 404 page, in the plain page
    ├── layouts/
    │   └── Base.astro            every page's document: head, fonts, ClientRouter, boot.ts
    ├── landing/                  the landing page
    │   ├── Landing.astro         the page: wordmark over swells, What, Who and How, install beside the panel, facts
    │   ├── copy.ts               the words the landing page adds to messaging.ts
    │   ├── landing.css           the landing page's styles
    │   └── landing.test.ts       the page tells the whole story
    ├── guide/                    the documentation page at /docs
    │   ├── Guide.astro           the page: nav, opening, sections, footer; starts notes.ts
    │   ├── Section.astro         one numbered section: prose, diagram, code, shots, extras, margin notes
    │   ├── content.ts            the sections, groups, limits, questions and install ways, as data and small HTML
    │   ├── parts.tsx             static parts: reference tables, flags, limits, questions, changelog, brand links, footer, note numbers
    │   ├── DocsNav.tsx           islands: the nav's section list with its moving mark, and the phone's jump menu
    │   ├── notes.ts              browser script: lines margin notes up with their markers, flashes a note on click
    │   ├── Install.tsx           island: the install tabs and the agent skill line
    │   ├── CodeBlocks.tsx        islands: code blocks, tabbed snippets and the copy button
    │   ├── code.ts               the TOML, shell and JSON highlighter
    │   ├── ConfigExplorer.tsx    island: snippet chips and the mock panel
    │   ├── explorer.ts           the explorer's model: made-up items, snippets, filtering, sorting, grouping
    │   ├── diagrams.tsx          the three static SVG diagrams, by id
    │   ├── diagrams.css          the diagrams' styles
    │   ├── figures.tsx           the Shot component, from shots.json
    │   ├── sailboat.tsx          the small sailboat mark
    │   ├── text.ts               prose helpers: no lone last words, numbered note markers
    │   ├── docs.css              the documentation's styles, also the base for the landing and plain pages
    │   └── *.test.ts(x)          highlighter, explorer, text helpers and diagrams
    ├── privacy/
    │   ├── Plain.astro           the plain page shell, used by /privacy and /404
    │   ├── OptOut.tsx            island: this browser's level and the opt-out buttons
    │   └── privacy.css           the plain page's styles
    ├── reference/
    │   ├── data.ts               REF: the virtual reference module, typed
    │   ├── parse.ts              pure parsers: schema to key tables, Markdown tables, skill keys, flags, Swift command table, inline Markdown
    │   ├── markdown.ts           block Markdown to HTML (PRIVACY.md), and the guide's HTML to Markdown (agent files)
    │   └── reference.test.ts     every schema key, command, preset and the version reach the page and the agent files
    ├── test/
    │   └── render.ts             renders a page with Astro's container, as the build does
    ├── messaging.ts              the name, one line, proof, links and install lines
    ├── meta.ts                   PAGES and headOf: each page's head
    ├── tokens.css                every colour, face, size and space
    ├── boot.ts                   browser start-up: error reporting, analytics, outbound clicks, client-navigation page views
    ├── analytics.ts              the tracker, the typed events, consent-aware track, opt-out and opt-in, page views
    ├── posthog.ts                the PostHog client, in its own lazy chunk
    ├── errors.ts                 the error queue and the lazy Sentry start
    ├── sentry.ts                 the Sentry client, in its own lazy chunk
    ├── consent.ts                the consent level from the address bar and local storage
    ├── actor.ts                  person or agent, the agent identity in session storage
    ├── visitor.ts                the visitor id in local storage
    ├── device.ts                 OS family, mobile, viewport class, the page id, the super properties
    ├── env.d.ts                  the build's env keys, __APP_VERSION__ and the virtual modules' types
    └── *.test.ts                 site-wide checks, consent, actor and visitor
```

### Build-time modules

**`plugins/site.ts`**, the build orchestrator.

- State: none between calls; `SOURCES` lists the repository files whose change reloads the dev server.
- `siteIntegration()`: the Astro integration.
  `astro:config:setup` adds `referenceModules()`; `astro:server:setup` adds the watcher and the middleware; `astro:build:done` writes `generatedFiles()` and the listed screenshots into `dist/`.
- `referenceModules()`: a Vite plugin resolving `virtual:shipyard-reference` to `referenceData()` as JSON, and `virtual:shipyard-privacy` to `PRIVACY.md` without its title, as HTML.
- `generatedFiles()`: the agent files plus `sitemap.xml`, by path.
- `sitemap()`: the listed pages from `PAGES`, plus `llms.txt` and `llms-full.txt`.

**`plugins/repo.ts`**, the repository reader.

- State: `SITE_DIR` and `REPO_DIR`.
- `referenceData()`: the whole reference as one object, `ReferenceData`.
- `appVersion()`, `presets()`, `latestRelease()`, `commandSources()`, `readRepo()`, `repoPath()`.
- Rule: only this file and the scripts touch the disk; `src/reference/parse.ts` stays pure.

**`plugins/agents.ts`**, the agent files.

- `buildAgentFiles(ref)`: `llms.txt`, `docs/<id>.md` per section and `llms-full.txt`.
- `sectionMd(section, ref)`: one section as Markdown, its extra rendered from `ref` or `content.ts`.
- `pagePath(section)`: `docs/<id>.md`.

**`scripts/check-public-bundle.mjs`**, the post-build gate.

- Reads `dist/` and the build's env.
- Fails on: a page without its required words, a missing required file, a vendor's code without its key, or a vendor's client in a chunk loaded up front.
- Prints each page's JavaScript on load, for its islands, and only when analytics load.

### Page modules

**`src/meta.ts`**: `PAGES`, `pageById(id)`, `absolute(path)`, `headOf(page)`.
It owns which pages exist and their heads; `Base.astro`, `plugins/site.ts` and `scripts/social.mjs` read it.

**`src/guide/content.ts`**: `SECTIONS`, `GROUPS`, `byId`, `LIMITS`, `QUESTIONS`, `INSTALL_WAYS`, `ext()`, and the `DocSection`, `Snippet` and `Lang` types.
A section's `extra` picks the generated or interactive part `Section.astro` shows; its `diagram` picks one of `DIAGRAMS`; its `shots` name `shots.json` ids.

**`src/landing/Landing.astro`**: the landing page, top to bottom.

- The wordmark set large in the serif over slow swell lines, and the one line.
- What, Who and How in three columns, one column on a phone, from `src/landing/copy.ts`.
- The install tabs and the line for telling an agent, beside the real panel: the screenshots `landing-tabs-dark` and `landing-list-light`, which also open the documentation page.
- The facts as one row, two columns on a phone.

Only the install tabs and the copy buttons hydrate.
`landing.css` reads every value from `src/tokens.css`.

**`src/guide/Guide.astro`**: lays out the nav, the opening, every section and the footer, and starts `notes.ts`.
**`src/guide/Section.astro`**: lays out one section from its `DocSection` and `NOTE_NUMBERS`.

**`src/guide/explorer.ts`**: `SNIPPETS`, `ITEMS`, `DEFAULT_CONFIG`, `configOf`, `listed`, `sorted`, `groups`, `attentionCount`, `mockPanel`.
It owns the mock's rules, kept to what the documentation states.

### Browser modules

**`src/analytics.ts`**.

- State: the module's `tracker` (queue up to 50, `started`, `stopped`), the loaded `posthog` module, `KEY` and `HOST`.
- `track(event, props)`: sends one typed event when there is a key and consent is `all`.
- `startAnalytics()`: loads PostHog when idle, unless there is no key or consent is `none`.
- `optOut(to)`, `optIn()`, `analyticsActive()`.
- `pageLeft()`, `pageShown()`: page leave and page view for client-side navigations.
- On import, it reads `?analytics_agent` and `?analytics_purpose`, saves a valid identity and removes both from the address bar.

**`src/consent.ts`**.

- State: `current`, resolved once on import from the address bar and `localStorage['shipyard:analytics']`.
- `consent()`, `setConsent(next)`, `resolveConsent(search, store)`, `safeStore()`.

**`src/errors.ts`**.

- State: `DSN`, resolved once on import, and the queue (early reports, sent count).
- `reportError(error, context)`, `startErrorReporting()`, `createErrorQueue(enabled, max)`.

**`src/actor.ts`** and **`src/visitor.ts`**.

- State: `sessionStorage['shipyard:agent']` and `localStorage['shipyard:visitor']`.
- `readAgentParams`, `loadAgent`, `saveAgent`, `forgetAgent`, `resolveActor`; `visitorId`, `forgetVisitor`, `randomUuid`.

### Copied modules

The privacy, analytics and error modules are kept as copies in three sites, not shared as a package.
Each project is small, so a shared package would cost more in publishing and versioning than the copies cost to keep in step.
A change to consent, the visitor id, the agent identity, PostHog or Sentry is made in all three copies:

| Site | Where the copies live | Storage key prefix | Consent levels |
| --- | --- | --- | --- |
| shipyard.yahyapak.dev | `src/consent.ts`, `src/actor.ts`, `src/visitor.ts`, `src/analytics.ts`, `src/posthog.ts`, `src/sentry.ts`, `src/errors.ts` in `site/` | `shipyard:` | `all`, `pageviews`, `none` |
| topographic.yahyapak.dev | `apps/playground/src/` in `yahyabedirhan/topographic`, with the same file names | `topographic:` | `all`, `pageviews`, `none` |
| yahyapak.dev | `src/privacy.js`, `src/analytics.js`, `src/errors.js` in `yahyabedirhan/personal-website` | none | `full`, `pageviews`, `off` |

This section is the one place that records the copies; the modules themselves carry no note about them.
The three sites send to one PostHog project and tell their events apart with the `site` super property, which this site sets in `src/device.ts`.

### Observations

These describe the code as it is; this document changes none of them.

- `src/guide/` holds parts the other pages share: `Landing.astro` imports `CodeBlocks.tsx`, `figures.tsx` and `docs.css`, and `Plain.astro` imports `docs.css`.
  `docs.css` is in effect the site's base stylesheet as well as the documentation's.
- `src/privacy/Plain.astro` is the 404 page's shell too, so the 404 page depends on the privacy folder.
- `src/guide/parts.tsx` mixes the generated reference tables, the text-only section extras, the brand links, the footer and the note numbering.
- `src/analytics.ts` mixes the tracker, consent-aware sending, the agent parameters read on import, and the page-view hooks for client navigations.
- `src/actor.ts` > `durationBucket` and `src/posthog.ts` > `setActor` have no caller outside tests.
- `DocSection` > `extra` allows `'layouts'`, but no section sets it and `Section.astro` has no branch for it.
- `PRIVACY.md` > 'Events' says `install_tab_changed` records "download, from source or Homebrew", but `INSTALL_WAYS` has only `download` and `source`.
- The landing page's install tabs don't send `install_tab_changed`, and its release and GitHub links carry no `data-out`, so `outbound_clicked` doesn't count them (`src/landing/Landing.astro`).
- The colours are repeated outside `tokens.css`: `Base.astro` > `theme-color`, `scripts/social.mjs` > `C` and `scripts/terminal.mjs` > `C`, each with a comment that it follows `tokens.css`.
- `Base.astro`'s comment says the head comes from `src/pages.ts`; it comes from `src/meta.ts`.
- `scripts/social.mjs` reads `src/messaging.ts` and `src/meta.ts` with regular expressions, so a change to how those constants are written can silently drop a card.
- **inferred**: a client-side navigation before PostHog has loaded sends no page view for the first page, because `pageShown` and `pageLeft` do nothing until the module has loaded and PostHog's own first page view is of the page shown when it loads.

---

## 4. Implementation

### A build

`npm run build`, from `site/`:

```text
npm run build                                                   package.json
├── astro check                                                 type-checks src/, plugins/, configs (tsconfig.json)
├── astro build
│   ├── load config                                             astro.config.ts
│   │   ├── SITE_URL                                            src/messaging.ts
│   │   ├── __APP_VERSION__ = appVersion()                      plugins/repo.ts  <- Sources/ShipyardCommand/Version.swift
│   │   └── siteIntegration()                                   plugins/site.ts
│   │       └── astro:config:setup -> add referenceModules()    plugins/site.ts
│   ├── render each route in src/pages/ to <file>.html          build.format = 'file'
│   │   ├── Base.astro: headOf(pageById(id))                    src/layouts/Base.astro, src/meta.ts
│   │   ├── import 'virtual:shipyard-reference'                 src/reference/data.ts
│   │   │   └── load -> referenceData()                         plugins/repo.ts
│   │   │       ├── schema/config.schema.json, cli.schema.json  -> configReference, cliReference (src/reference/parse.ts)
│   │   │       ├── skills/shipyard/SKILL.md, presets.md, references/notices.md -> skillKeys, presets, flagTable
│   │   │       ├── Sources/**/*Command*.swift                  -> commandReference
│   │   │       └── CHANGELOG.md                                -> latestRelease
│   │   ├── import 'virtual:shipyard-privacy'                   PRIVACY.md -> blockMd (src/reference/markdown.ts)
│   │   ├── Guide.astro -> Section.astro per SECTIONS entry     src/guide/
│   │   │   └── Shot(id) looks id up in shots.json              src/guide/figures.tsx  (throws when missing)
│   │   └── islands render to HTML; their code goes to dist/_astro/ as hashed chunks
│   ├── copy public/ into dist/                                 _headers, robots.txt, og/, favicons, logo
│   └── astro:build:done                                        plugins/site.ts
│       ├── write generatedFiles()                              llms.txt, llms-full.txt, docs/<id>.md, sitemap.xml
│       │   └── buildAgentFiles(referenceData())                plugins/agents.ts
│       └── copy assets/screenshots/launch/<id>.png listed in shots.json -> dist/shots/
└── node scripts/check-public-bundle.mjs                        each page's words, required files, vendor code, sizes
```

State after: `dist/` holds `index.html`, `docs.html`, `privacy.html`, `404.html`, `_astro/`, `shots/`, `docs/*.md`, the agent files, the sitemap and `public/`'s files.

### A page load with island hydration

A browser opens `/docs`:

```text
GET /docs                                                       Cloudflare assets, html_handling auto-trailing-slash -> docs.html
├── headers                                                     public/_headers: no-cache HTML, nosniff, referrer policy
├── HTML renders with JavaScript off                            whole page from the build
├── <script> import '../boot'                                   src/layouts/Base.astro, runs once per full load
│   ├── import analytics.ts -> import consent.ts                src/consent.ts: current = resolveConsent(location.search, localStorage)
│   │   └── on import: read ?analytics_agent/_purpose, save if valid and consent is all, strip from URL   src/analytics.ts
│   ├── startErrorReporting()                                   src/errors.ts: without DSN or consent all, nothing
│   │   └── window error buffer, then on idle: import('./sentry') -> startSentry -> queue.attach
│   ├── startAnalytics()                                        src/analytics.ts: without key or with consent none, nothing
│   │   └── on idle: tracker.start() -> load()
│   │       ├── doNotTrack() -> stop                            src/analytics.ts
│   │       ├── import('./posthog')                             src/posthog.ts, its own chunk
│   │       ├── props = superProperties() (+ actorProps() when consent is all)   src/device.ts, src/actor.ts, src/visitor.ts
│   │       └── startPostHog -> init (cookieless, first $pageview) and flush the queue
│   └── document listeners: click a[data-out], astro:before-swap, astro:after-swap   src/boot.ts
├── <script> import './notes'                                   src/guide/Guide.astro -> src/guide/notes.ts
│   └── astro:page-load -> start(): place margin notes, observe resizes
└── islands hydrate
    ├── NavSections client:media="(min-width: 1041px)"          src/guide/DocsNav.tsx: scroll spy moves the sailboat mark
    ├── JumpMenu client:media="(max-width: 1040px)"             src/guide/DocsNav.tsx
    └── client:visible as each scrolls in: Install, CodeTabs, CodeBlock, ConfigExplorer   src/guide/Section.astro
        └── a copy click -> track('code_copied', { target })    src/guide/CodeBlocks.tsx -> src/analytics.ts
            └── KEY and consent all ? tracker.track : nothing   queued until the client loads
```

### A client-side navigation with a page view

A reader on `/docs` clicks the wordmark, a link to `/`:

```text
click <a href="/">                                              ClientRouter (src/layouts/Base.astro) takes it; data-astro-prefetch fetched it on hover
├── astro:before-swap
│   ├── pageLeft()                                              src/boot.ts -> src/analytics.ts
│   │   └── posthog loaded and consent not none ? capturePageLeave()   src/posthog.ts: $pageleave while the URL is still /docs
│   └── notes.ts teardown()                                     src/guide/notes.ts
├── swap the body to index.html's                               boot.ts does not run again
├── astro:after-swap
│   └── pageShown()                                             src/boot.ts -> src/analytics.ts
│       └── capturePageView(pageOf())                           src/device.ts: 'home'; src/posthog.ts: register page, $pageview
└── astro:page-load -> notes.ts start(): no .sec on the landing page, so it returns
```

A link marked `data-astro-reload`, such as `llms.txt` or `configuration.md`, skips the router and loads in full (`src/guide/parts.tsx` > `Footer`).

### Consent and opt-out

A visitor opens `/privacy?analytics_optout` and later presses **Send nothing**:

```text
GET /privacy?analytics_optout
└── import consent.ts                                           src/consent.ts
    ├── resolveConsent: optOut without "all" -> 'pageviews', saved under shipyard:analytics
    ├── strip analytics_optout from the address bar
    └── not all -> forgetVisitor(localStorage), forgetAgent(sessionStorage)   src/visitor.ts, src/actor.ts
├── errors.ts: DSN = undefined (consent is not all)             no Sentry this page
├── startAnalytics(): key and consent pageviews -> load later   PostHog without actor props
│   └── track(...) for custom events -> dropped (consent is not all)
└── OptOut island hydrates -> setLevel(consent()) = 'pageviews' src/privacy/OptOut.tsx

click "Send nothing"
└── optOut('none')                                              src/analytics.ts
    ├── from 'pageviews': no final event; tracker.stop()
    └── setConsent('none')                                      src/consent.ts: saved; visitor and agent forgotten again
        next full load: consent none -> createTracker(undefined) and startAnalytics returns: no client loads
```

From `all`, `optOut` first sends one `analytics_opted_out` event with `from: 'all'`, starts the tracker so it is delivered, then stops it (`src/analytics.ts`, `src/consent.test.ts`).

### A 404 through the Worker

```text
GET /nope  (Accept: text/html)                                  no file in dist/ matches; not_found_handling "none"
└── worker.fetch(request, env)                                  worker/index.js
    ├── wantsPage: GET and Accept has text/html
    ├── env.ASSETS.fetch('/404') -> 404.html                    built from src/pages/404.astro
    └── Response(page.body, 404, text/html)

GET /nope.json  (curl, an agent)
└── worker.fetch -> Response("Not found. ... llms.txt", 404, text/plain)
```

### A deploy

```text
push to main
└── Workers Builds, trigger "Deploy production", root site/      keys from the trigger's build variables
    ├── npm ci, Node from engines in site/package.json
    ├── npm run build                                           the build above
    └── npx wrangler deploy                                     site/wrangler.jsonc
        ├── upload dist/ as static assets (binding ASSETS)
        ├── upload worker/index.js as the Worker's main
        └── route shipyard.yahyapak.dev as a custom domain      Cloudflare makes the DNS record and certificate
```

### A rejected build

A change drops the configuration reference's `menu.layout` row from the page:

```text
npm run build
├── astro check                                                 passes
├── astro build                                                 passes: docs.html is written without data-key="menu.layout"
└── check-public-bundle.mjs
    ├── pages['docs.html'] = ['What it is', 'data-key="menu.layout"']
    ├── html.includes('data-key="menu.layout"') -> false
    ├── leaks.push('docs.html has no "data-key="menu.layout"" in its HTML')
    └── print "the public build is not as it must be:" and exit 1  -> npm run build fails, CI fails, deploy never runs
```

`npm test` would already fail first: `src/reference/reference.test.ts` > 'lists every key of config.schema.json on the page' renders the guide and finds the key missing.
A section naming a screenshot id that `shots.json` lacks fails one step earlier still: `Shot` throws while `astro build` renders, and `src/site.test.ts` > 'cover every id the pages use' fails in `npm test`.

---

## 5. Extensibility

| Change | What you touch |
|---|---|
| Add a documentation section | One entry in `SECTIONS` and its id in a `GROUPS` group (`src/guide/content.ts`). The nav, the note numbers, `docs/<id>.md`, `llms.txt` and `llms-full.txt` follow. |
| Add a section with a new generated or interactive part | A new `extra` value in `DocSection`, a branch in `Section.astro`, the part in `parts.tsx` or a new island, and a case in `plugins/agents.ts` > `extra` so the Markdown carries it too. |
| Add a diagram | A component in `src/guide/diagrams.tsx`, its id in `DIAGRAMS` and `DocSection` > `diagram`, and the section that shows it. `diagrams.test.tsx` checks its title, ids and use. |
| Add a page | A route in `src/pages/`, its entry in `PAGES` with a new `PageMeta` id (`src/meta.ts`), its page component in a folder of its own under `src/`, `npm run social` for its card, `public/_headers` for its path, and `pageOf` in `src/device.ts` if analytics should name it. Add its required words to `check-public-bundle.mjs` > `pages`. |
| Add a screenshot | An entry in `site/shots.json` with its capture steps, the PNG in `assets/screenshots/launch/` from those steps, then its id in a section's `shots` or a `<Shot id>`. The build copies it to `/shots/`. |
| Retake the help screenshot | `npm run terminal` after the command's help changes. |
| Add an analytics event | Its name and typed props in `AnalyticsEvents` and `EVENT_NAMES` (`src/analytics.ts`), the `track` call in the island, and its row in `PRIVACY.md` > 'Events', which `consent.test.ts` checks. |
| Count a new outbound link | `data-out` with an `OutboundTarget`, or the `Out` component (`src/guide/parts.tsx`); a new target extends `OutboundTarget` and `PRIVACY.md`. |
| Add a configuration key to the reference | Nothing in the site: the key comes from `schema/config.schema.json`. A new top-level table also needs its row in `OWNERS` (`src/reference/parse.ts`). |
| Add a configuration key to the explorer | A field in `MockConfig` and `DEFAULT_CONFIG`, its rule in `listed`, `sorted` or `groups`, a snippet in `SNIPPETS` (`src/guide/explorer.ts`), and a case in `explorer.test.ts`. |
| Add a command | Nothing in the site: the command reference reads the Swift command table. |
| Change a colour, size or face | `src/tokens.css`. For the cards and the help screenshot, also `C` in `scripts/social.mjs` or `scripts/terminal.mjs`, then rerun them; for the browser bar, `theme-color` in `Base.astro`. |
| Change the one line or a link | `docs/messaging.md` first, then `src/messaging.ts`; rerun `npm run social` for the cards. |
| Change the landing page's words | `src/landing/copy.ts`; `landing.test.ts` checks they reach the page. |
| Change the privacy text | `site/PRIVACY.md`; the page and the dev server pick it up. |
| Add an agent name or purpose | `AGENT_NAMES` or `PURPOSES` (`src/actor.ts`) and the lists in `PRIVACY.md` > 'People and agents'. |
| Serve a new kind of file | Its cache and content type in `public/_headers`; a generated one goes in `plugins/site.ts` > `generatedFiles`, which serves it in development and writes it after the build. |
