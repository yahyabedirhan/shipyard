# Privacy

This page explains what the shipyard website at https://shipyard.yahyapak.dev collects when you or an AI agent read it, what it never collects, why, where the data goes, and how to opt out. It covers the website only.

## The app

The shipyard app and the `shipyard` command contain no analytics and no crash reporting. The app talks to GitHub as you, to sign in, to read what your projects list and to show your profile picture. It reaches Notion only through `ntn` after you connect it, your other machines only through Herdr when your `config.toml` names them, and the npm registry through `npx skills` when you install or update the agent skill from its panel.

## What the website collects

- Page views: the page, the site you came from, and the time on the page.
- Which copy buttons, install tabs, config explorer snippets and outbound links are used, never what was copied. The Events section lists each one.
- Your browser's type, screen size, language and timezone.
- One random visitor id, saved in your browser, so return visits count once.
- Whether a visit comes from a person or an AI agent.
- Crash reports from the page.

## What the website never collects

- It never sets cookies and never fingerprints your browser.
- It never stores your IP address, and never collects your name, email or any account.
- It never collects text you type or the text of what you copy.
- It never records sessions, heatmaps or clicks on its own.

## Opting out

Add one of these to any page's address:

| Parameter | Effect |
| --- | --- |
| `?analytics_optout` | Pageviews only: no other events and no error reports. |
| `?analytics_optout=all` | Nothing is sent. The analytics and error scripts are not loaded. |
| `?analytics_optin` | Undoes either. |

The choice is saved in the browser's local storage under `shipyard:analytics`, so each browser and device keeps its own and must opt out separately. Clearing site data resets it. Either opt out also deletes the visitor id and the tab's agent id. Browsers with Do Not Track on send no analytics.

## Pageviews

Each page view records the page, the site you came from, any campaign tags in the link, and the time on the page. Your browser also shares its type, screen size, language and timezone. Your IP address is never stored, and your country and city are not recorded.

## Visitor id

The first visit saves a random id in your browser under `shipyard:visitor`, so return visits count once. It holds nothing about you. Opting out deletes it.

## People and agents

AI agents are counted apart from people. An agent gets its own random id for one browser tab. Browsers run by automation, such as Playwright, count as agents.

An agent can say which agent it is and why it is here with `?analytics_agent=<name>&analytics_purpose=<purpose>` on its first page. This is optional, and only these values are recorded:

- Names: claude, chatgpt, gemini, jules, copilot, cursor, windsurf, opencode, pi, amp, droid, cline, roo, kilo, aider, goose, kiro, devin, manus, grok, perplexity, other.
- Purposes: testing, demo, creating, exploring, integrating, research, reverse-engineering, other.

## Events

Every event also carries: the site and app name, the version the docs describe, a coarse screen class such as phone, tablet or desktop, mobile or desktop, OS family, which page it was on, and the random visitor id.

| Event | Contains | Why |
| --- | --- | --- |
| `code_copied` | Which kind of block was copied: the download, the source build, the agent skill, the Herdr plugin, a configuration snippet, a command or other code. Never the text | To see how people install and configure shipyard |
| `install_tab_changed` | Which install tab was picked: download, from source or Homebrew | To see which way in people want |
| `explorer_snippet_picked` | The id of the config explorer snippet picked, such as `tabs` | To see which settings people look for |
| `outbound_clicked` | Which kind of link left the site: GitHub, the releases, the changelog, the Herdr plugin or yahyapak.dev, never its address | To see which links are useful |
| `analytics_opted_out` | The previous level: all, or pageviews only | Sent once when you opt out, to count opt outs |

## Error reports

Sentry receives crash reports from the page: the error message and stack trace, browser and OS, and the page path without the query string. There is no user data, cookies, headers, tracing or replay, and one page sends at most 10 reports.

## Where it goes

- **PostHog:** analytics, stored in the EU.
- **Sentry:** error reports, stored in the EU.
