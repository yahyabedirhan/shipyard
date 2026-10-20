import { useState } from 'react';
import SHOTS from '../../shots.json';
import { track } from '../analytics';
import { CodeBlock } from './CodeBlocks';
import { SNIPPETS, ageLabel, configOf, mockPanel, type Group, type MockConfig, type MockItem } from './explorer';

export interface ShotEntry { id: string; shows: string; state: string; appearance: string; layout: string; path: string; status: 'placeholder' | 'done' }
const BY_ID = Object.fromEntries((SHOTS.shots as ShotEntry[]).map((s) => [s.id, s]));

/** The address a finished screenshot is served at: the build copies assets/screenshots/launch/ to /shots/. */
export const shotSrc = (id: string) => `/shots/${id}.png`;

/**
 * A screenshot of the real app, by its id in shots.json. Until its status is done, it shows a placeholder frame
 * with what the picture must show, so a page never claims a picture it doesn't have.
 */
export function Shot({ id, caption, className }: { id: string; caption?: string; className?: string }) {
  const s = BY_ID[id];
  if (!s) throw new Error(`no shot ${id} in shots.json`);
  return (
    <figure className={`fig shot${className ? ` ${className}` : ''}`} data-shot={id}>
      {s.status === 'done'
        ? <img src={shotSrc(id)} alt={s.shows} loading="lazy" />
        : (
          <div className="shot-ph" role="img" aria-label={`Screenshot to come: ${s.shows}`}>
            <span className="shot-tag">Screenshot to come · {s.appearance} · {s.layout}</span>
            <span className="shot-what">{s.shows}</span>
            <code className="shot-id">{id}</code>
          </div>
        )}
      <figcaption className="cap">{caption ?? s.shows}</figcaption>
    </figure>
  );
}

/* ---------------------------------------------------------------- the config explorer */

const DOT: Record<MockItem['state'], string> = {
  open: 'open', draft: 'draft', merged: 'merged', closed: 'closed', running: 'running', failed: 'closed', succeeded: 'open',
};
const GLYPH: Record<MockItem['kind'], string> = { 'pull-requests': '⇄', pings: '●', issues: '◎', 'workflow-runs': '▸' };

function MockRow({ item, all }: { item: MockItem; all: boolean }) {
  const ref = item.number ? `${item.repo.split('/')[1]}#${item.number}` : item.repo.split('/')[1];
  return (
    <li className={`m-row${item.state === 'draft' ? ' draft' : ''}`}>
      <span className={`m-glyph s-${DOT[item.state]}`} aria-hidden="true">{GLYPH[item.kind]}</span>
      <span className="m-title">{item.title}</span>
      <span className="m-meta">{all ? `${item.project} · ` : ''}{ref} · {item.author} · {ageLabel(item.age)}</span>
      {item.attention && item.state !== 'merged' && item.state !== 'closed' && item.state !== 'succeeded' ? <span className="m-attn" aria-label="needs attention" /> : null}
    </li>
  );
}

function MockGroups({ groups, sub, all }: { groups: Group[]; sub: boolean; all: boolean }) {
  return (
    <>
      {groups.map((g, i) => (
        <div className="m-group" key={g.name || i}>
          {g.name && sub ? <div className="m-sub"><span>{g.name}</span><span>{g.count}</span></div> : i > 0 ? <hr className="m-div" /> : null}
          <ul>{g.rows.map((r) => <MockRow key={`${r.repo}${r.number ?? r.title}`} item={r} all={all} />)}</ul>
          {g.more ? <div className="m-more">Show {g.more} more</div> : null}
        </div>
      ))}
    </>
  );
}

/** A mock of the panel drawn in HTML from the explorer's model. It says it is a mock. */
export function MockPanel({ config }: { config: MockConfig }) {
  const panel = mockPanel(config);
  const sub = config.subsections ?? config.layout === 'tabs';
  return (
    <div className="mock" aria-label="A mock of the shipyard panel, drawn for these docs">
      <div className="m-bar"><span className="m-icon" aria-hidden="true">{RINGS.A}</span><span className="m-count">{panel.attention}</span><span className="m-badge">Mock</span></div>
      <div className="m-panel">
        {panel.tabs ? <div className="m-tabs" role="presentation">{panel.tabs.map((t, i) => <span key={t} className={i === 0 ? 'on' : undefined}>{t}</span>)}</div> : null}
        {panel.projects.map((p) => (
          <section key={p.slug} className="m-project">
            {panel.tabs ? null : <div className="m-head"><b>{p.title}</b><span>{p.count}</span></div>}
            <MockGroups groups={p.groups} sub={sub} all={Boolean(panel.tabs)} />
          </section>
        ))}
      </div>
    </div>
  );
}

/** Snippets of config.toml, each with its effect on the mock panel. */
export function ConfigExplorer() {
  const [i, setI] = useState(0);
  const s = SNIPPETS[i];
  return (
    <figure className="fig explorer" id="fig-explorer">
      <div className="chips" role="tablist" aria-label="Snippet">
        {SNIPPETS.map((x, j) => (
          <button key={x.id} type="button" role="tab" aria-selected={j === i} onClick={() => { setI(j); track('explorer_snippet_picked', { snippet: x.id }); }}>{x.label}</button>
        ))}
      </div>
      <div className="ex-grid">
        <div className="ex-code">
          <CodeBlock code={s.toml} lang="toml" target="config" />
          <p className="ex-what">{s.what}</p>
        </div>
        <MockPanel config={configOf(s)} />
      </div>
      <figcaption className="cap">A mock drawn in HTML from made-up items, not a screenshot of the app.</figcaption>
    </figure>
  );
}

/* ---------------------------------------------------------------- the sidebar ring */

/**
 * The small mark beside the current section in the nav, after topographic's ring of contours: three strokes,
 * faint to strong, that glide to the section being read with a wobble. A is the logo's sailboat, B a hull on two
 * waves, C three swells. `?ring=A|B|C` switches it in development; a build shows the default.
 */
export const RINGS = {
  A: (
    <svg viewBox="0 0 34 24" aria-hidden="true">
      <path d="M5 16.5h24l-3.6 4.5H8.6z" />
      <path d="M15.5 5.5v9h-7.5z" />
      <path d="M17.5 2.5v12h9.5z" />
    </svg>
  ),
  B: (
    <svg viewBox="0 0 34 24" aria-hidden="true">
      <path d="M2 21c3-2 6-2 9 0s6 2 9 0 6-2 9 0 3 1.4 3 1.4" />
      <path d="M3.5 17.2c2.6-1.7 5.3-1.7 7.9 0s5.3 1.7 7.9 0 5.3-1.7 7.9 0 3 1.2 3 1.2" />
      <path d="M9.5 10.5h15l-2.6 4H12.1zM17 10.5V3l5 6.2" />
    </svg>
  ),
  C: (
    <svg viewBox="0 0 34 24" aria-hidden="true">
      <path d="M2.5 19.5c4-11 25-11 29 0" />
      <path d="M7.5 19.5c3-6.6 16-6.6 19 0" />
      <path d="M12.5 19.5c1.8-3 7.2-3 9 0" />
    </svg>
  ),
} as const;
export type RingId = keyof typeof RINGS;
export const DEFAULT_RING: RingId = 'A';

/** The ring for this page: `?ring=` in development, the default otherwise. */
export function ringFrom(search: string, dev: boolean): RingId {
  const q = new URLSearchParams(search).get('ring')?.toUpperCase();
  return dev && q && q in RINGS ? (q as RingId) : DEFAULT_RING;
}
