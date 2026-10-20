# Landing page prototype

This folder is a prototype on the review branch `feat/site-landing-variants`, not a finished page. It answers one question: what the first screen of `shipyard.yahyapak.dev` should look like. The docs stay at `/docs`.

The variants sit on one route, `/`, and a floating bar at the bottom switches between them (its arrows, or the ← and → keys). The choice is kept in `?variant=`, so a link opens the same one. The bar shows only in development: a production build leaves it out and shows variant A.

| Id | Name | Shape |
| --- | --- | --- |
| `A` | One column | One narrow column read top to bottom, like the docs' opening: the line, three sentences, the panel, two numbered steps, the facts. |
| `B` | Menu bar | A menu bar strip across the top with shipyard's item in it, the panel hanging from it on the right, the story and the install lines on the left. |
| `C` | Terminal | The terminal is the page: the three steps as one session, the panel and the facts beside it, the copyable lines under it. |
| `D` | Swells | An artistic opening: slow swells across the screen, the wordmark set large, What, Who and How in three columns, the panel rising beside the install lines. |

Every variant tells the same story in one screen: the one line, the real panel (the `readme-hero-dark` screenshot, a placeholder until it's captured), the install lines, the line for telling an agent to use it, and the way to the docs and the install section.

In development, `?line=A`, `B` or `C` shows each candidate one line from `src/messaging.ts`, so a variant can be judged with each.

Run it from `site/` with `npm install` and `npm run dev`, then open `http://localhost:5173/?variant=A`.

When a variant wins, fold it into a real page, drop the others and `src/prototype/Switcher.tsx` from `main`, and keep this branch as the record of what was tried.
