# Landing page

This folder is the landing page at `/` of `shipyard.yahyapak.dev`. The docs are at `/docs`.

## Shape

- `Landing.astro` is the page, top to bottom:
  - the wordmark set large in the serif over slow swell lines, and the one line;
  - What, Who and How in three columns (one column on a phone);
  - the install lines and the line for telling an agent, beside the real panel;
  - the facts as one row (two columns on a phone).
- `copy.ts` holds the words the page adds to `src/messaging.ts`: what it is, who it is for, how it is used and the facts.
- `landing.css` styles the page. It reads every value from `src/tokens.css`.
- `landing.test.ts` checks that the page tells the whole story.

The page is HTML at build time and reads with JavaScript off.
Only the install tabs and the copy buttons hydrate, as React islands from `src/docs/CodeBlocks.tsx`.

## The panel image

The panels are two screenshots side by side, `landing-tabs-dark` and `landing-list-light`, marked in `Landing.astro` with shot comments and listed in `site/shots.json`.
The docs page opens with the same pair.
Until a screenshot is captured, the `Shot` component shows a placeholder frame.
`npm run placeholders` lists the screenshots still to take.

## Running it

Run `npm install` and `npm run dev` in `site/`, then open `http://localhost:4321/`.
