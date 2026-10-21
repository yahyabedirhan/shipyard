// The docs' explanatory diagrams: static SVG drawn from fixed geometry, with no state and no effects, so each one
// renders the same on the server and ports to any framework as it is. They follow the Graphite look: each diagram is
// a dark granite tile with a double rim, ordinary nodes are crisp outlined paper, and only shipyard itself (and at
// most one arrow) folds, as the logo does. Colours and type sizes come from tokens.css through diagrams.css.
import type { ReactNode } from 'react';
import './diagrams.css';

/* ---------------------------------------------------------------- primitives */

interface Box { x: number; y: number; w: number; h: number }

/** The ids one diagram's defs use, prefixed so several diagrams can share a page. */
const ids = (slug: string) => ({ ground: `${slug}-ground`, rim: `${slug}-rim`, rimIn: `${slug}-rim-in`, arrow: `${slug}-arrow`, fold: `${slug}-fold`, title: `${slug}-title`, desc: `${slug}-desc` });
type Ids = ReturnType<typeof ids>;

/** Rough widths of set text, in the diagram's units: the mono face is 0.6 em a character, plus its tracking. */
const monoWidth = (text: string, size: number, tracking = 0) => text.length * size * (0.6 + tracking);

/** The tile: the ground gradient, the arrowheads, and the two rim gradients the frame draws last. */
function Defs({ id, h }: { id: Ids; h: number }) {
  return (
    <defs>
      <linearGradient id={id.ground} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2={h}>
        <stop offset="0" className="dg-stop-tile-top" />
        <stop offset="1" className="dg-stop-tile-bottom" />
      </linearGradient>
      <linearGradient id={id.rim} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2={h}>
        <stop offset="0" className="dg-stop-rim-top" />
        <stop offset="1" className="dg-stop-rim-bottom" />
      </linearGradient>
      <linearGradient id={id.rimIn} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2={h}>
        <stop offset="0" className="dg-stop-rim-in-top" />
        <stop offset="1" className="dg-stop-rim-in-bottom" />
      </linearGradient>
      <marker id={id.arrow} viewBox="0 0 8 8" refX="8" refY="4" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto">
        <path d="M0 0.5 8 4 0 7.5z" className="dg-head" />
      </marker>
      {/* the folded head: a triangle split along its axis, one half in the fold's shade */}
      <marker id={id.fold} viewBox="0 0 14 12" refX="14" refY="6" markerWidth="14" markerHeight="12" markerUnits="userSpaceOnUse" orient="auto">
        <path d="M0 0 14 6 0 6z" className="dg-head-fold" />
        <path d="M0 12 14 6 0 6z" className="dg-head-shade" />
      </marker>
    </defs>
  );
}

/** The double rim inside the tile's edge, drawn after everything else so no fill covers it. */
function Rims({ id, w, h }: { id: Ids; w: number; h: number }) {
  return (
    <g fill="none" strokeWidth="1">
      <rect x="2.5" y="2.5" width={w - 5} height={h - 5} rx="10" stroke={`url(#${id.rim})`} />
      <rect x="10.5" y="10.5" width={w - 21} height={h - 21} rx="2" stroke={`url(#${id.rimIn})`} />
    </g>
  );
}

/** The whole figure: an accessible SVG named by its title and description, scrolling inside its own box on a phone. */
function Diagram({ slug, w, h, title, desc, caption, children }: { slug: string; w: number; h: number; title: string; desc: string; caption?: string; children: (id: Ids) => ReactNode }) {
  const id = ids(slug);
  return (
    <figure className="fig dg" data-diagram={slug}>
      <div className="dg-scroll">
        <svg viewBox={`0 0 ${w} ${h}`} role="img" aria-labelledby={`${id.title} ${id.desc}`} className="dg-svg">
          <title id={id.title}>{title}</title>
          <desc id={id.desc}>{desc}</desc>
          <Defs id={id} h={h} />
          <rect width={w} height={h} rx="12" fill={`url(#${id.ground})`} />
          {children(id)}
          <Rims id={id} w={w} h={h} />
        </svg>
      </div>
      {caption ? <figcaption className="cap">{caption}</figcaption> : null}
    </figure>
  );
}

/** A small uppercase label above a group, in the mono face. */
const Eyebrow = ({ x, y, children }: { x: number; y: number; children: string }) => <text x={x} y={y} className="dg-eyebrow">{children}</text>;

/** The rectangular type tag in a node's top-left corner. */
function Tag({ x, y, text, folded }: { x: number; y: number; text: string; folded?: boolean }) {
  const w = Math.round(monoWidth(text, 8.5, 0.1) + 10);
  return (
    <g>
      <rect x={x} y={y} width={w} height="14" className={folded ? 'dg-tag-box on-fold' : 'dg-tag-box'} />
      <text x={x + 5} y={y + 10} className={folded ? 'dg-tag on-fold' : 'dg-tag'}>{text}</text>
    </g>
  );
}

interface NodeProps { b: Box; tag: string; name: string; sub?: string; children?: ReactNode; nameY?: number }

/** An ordinary node: paper filled like the tile's top, outlined, with a tag, a name and a technical sublabel. */
function Node({ b, tag, name, sub }: NodeProps) {
  const cx = b.x + b.w / 2;
  return (
    <g>
      <rect x={b.x} y={b.y} width={b.w} height={b.h} rx="2" className="dg-node" />
      <Tag x={b.x + 8} y={b.y + 8} text={tag} />
      <text x={cx} y={b.y + 44} className="dg-name">{name}</text>
      {sub ? <text x={cx} y={b.y + 61} className="dg-sub">{sub}</text> : null}
    </g>
  );
}

/** The focal node, folded: white paper with its top-right corner turned down as a 14-unit dog-ear, and no outline. */
function Folded({ b, tag, name, sub, children, nameY = 44 }: NodeProps) {
  const ear = 14;
  const r = b.x + b.w;
  const cx = b.x + b.w / 2;
  return (
    <g>
      <path d={`M${b.x} ${b.y}H${r - ear}L${r} ${b.y + ear}V${b.y + b.h}H${b.x}z`} className="dg-fold" />
      <path d={`M${r - ear} ${b.y}V${b.y + ear}H${r}z`} className="dg-fold-ear" />
      <Tag x={b.x + 8} y={b.y + 8} text={tag} folded />
      <text x={cx} y={b.y + nameY} className="dg-name on-fold">{name}</text>
      {sub ? <text x={cx} y={b.y + nameY + 17} className="dg-sub on-fold">{sub}</text> : null}
      {children}
    </g>
  );
}

/** A connector, drawn before the nodes so they sit on top of it. */
function Arrow({ d, id, folded, dashed }: { d: string; id: Ids; folded?: boolean; dashed?: boolean }) {
  return <path d={d} className={`dg-arrow${folded ? ' folded' : ''}${dashed ? ' dashed' : ''}`} markerEnd={`url(#${folded ? id.fold : id.arrow})`} />;
}

/**
 * An arrow's label, on a mask filled with the ground's own gradient so it matches whatever lies behind it. `side`
 * sets it beside a vertical segment (`right`) or above or below a horizontal one (`above`, `below`), with a gap from the stroke.
 */
function Label({ x, y, text, id, side }: { x: number; y: number; text: string; id: Ids; side: 'right' | 'above' | 'below' }) {
  const w = Math.round(monoWidth(text, 9, 0.08) + 8);
  const h = 14;
  const bx = side === 'right' ? x + 6 : x - w / 2;
  const by = side === 'right' ? y - h / 2 : side === 'above' ? y - 8 - h : y + 8;
  return (
    <g>
      <rect x={bx} y={by} width={w} height={h} fill={`url(#${id.ground})`} />
      <text x={bx + 4} y={by + 10} className="dg-label">{text}</text>
    </g>
  );
}

/** Left-aligned lines of upright callout text. */
function Lines({ x, y, lines, className = 'dg-callout' }: { x: number; y: number; lines: string[]; className?: string }) {
  return <text x={x} y={y} className={className}>{lines.map((l, i) => <tspan key={i} x={x} dy={i ? 17 : 0}>{l}</tspan>)}</text>;
}

/* ---------------------------------------------------------------- how shipyard works */

/** What shipyard reads, the refresh that turns it into one menu model, and the three places you see the result. */
export function HowItWorks() {
  const W = 640;
  const H = 448;
  const src = [
    { tag: 'API', name: 'GitHub', sub: 'gh or sign-in' },
    { tag: 'PINGS', name: 'This Mac', sub: 'shipyard ping send' },
    { tag: 'PINGS', name: 'Other machines', sub: 'Herdr, every 30 s' },
    { tag: 'NOTES', name: 'Notion', sub: 'ntn, every minute' },
  ].map((s, i) => ({ ...s, b: { x: 24 + i * 152, y: 52, w: 136, h: 76 } }));
  const app: Box = { x: 24, y: 172, w: 592, h: 124 };
  const steps = ['Resolve repos', 'Fetch items', 'Filter', 'Find changes', 'Publish'];
  const out = [
    { tag: 'MENU BAR', name: 'One number', sub: 'items that need you' },
    { tag: 'PANEL', name: 'Your projects', sub: 'every item, grouped' },
    { tag: 'MACOS', name: 'Notifications', sub: 'by your rules' },
  ].map((s, i) => ({ ...s, b: { x: 24 + i * 204, y: 344, w: 184, h: 76 } }));
  return (
    <Diagram
      slug="how-it-works" w={W} h={H}
      title="How shipyard works"
      desc="GitHub, your agents' pings from this Mac and from other machines, and your Notion notes feed one refresh in the app, which turns them into the menu bar's number, the panel's projects and macOS notifications."
      caption="Pings and notes join the listings without spending GitHub requests. The refresh runs every two minutes by default, and stretches to stay within its share of your rate limit."
    >
      {(id) => (
        <>
          <Eyebrow x={24} y={40}>SOURCES</Eyebrow>
          {src.map((s) => <Arrow key={s.name} id={id} d={`M${s.b.x + s.b.w / 2} ${s.b.y + s.b.h}V${app.y}`} />)}
          <Arrow id={id} folded d={`M${out[0].b.x + out[0].b.w / 2} ${app.y + app.h}V${out[0].b.y}`} />
          {out.slice(1).map((o) => <Arrow key={o.name} id={id} d={`M${o.b.x + o.b.w / 2} ${app.y + app.h}V${o.b.y}`} />)}
          {src.map((s) => <Node key={s.name} {...s} />)}
          {out.map((o) => <Node key={o.name} {...o} />)}
          <Folded b={app} tag="APP" name="Shipyard.app" sub="one refresh, into one menu model" nameY={30}>
            {steps.map((s, i) => {
              const x = app.x + 16 + i * 114;
              return (
                <g key={s}>
                  <rect x={x} y={app.y + 64} width="104" height="44" rx="2" className="dg-chip" />
                  <text x={x + 52} y={app.y + 81} className="dg-chip-n">{String(i + 1).padStart(2, '0')}</text>
                  <text x={x + 52} y={app.y + 98} className="dg-chip-t">{s}</text>
                </g>
              );
            })}
          </Folded>
        </>
      )}
    </Diagram>
  );
}

/* ---------------------------------------------------------------- the configuration loop */

/** An edit's round trip: you ask, the agent edits, the app rereads and writes its verdict, the agent reads it. */
export function ConfigLoop() {
  const W = 640;
  const H = 300;
  const col = (i: number) => 24 + i * 216;
  const you: Box = { x: col(0), y: 40, w: 160, h: 76 };
  const agent: Box = { x: col(1), y: 40, w: 160, h: 76 };
  const file: Box = { x: col(2), y: 40, w: 160, h: 76 };
  const app: Box = { x: col(2), y: 172, w: 160, h: 76 };
  const verdict: Box = { x: col(1), y: 172, w: 160, h: 76 };
  const mid = (b: Box) => b.x + b.w / 2;
  return (
    <Diagram
      slug="config-loop" w={W} h={H}
      title="The configuration loop"
      desc="You ask your agent for a change; it edits config.toml with the shipyard skill; the app rereads the file on save and writes its verdict to config-status.json; the agent reads the verdict and fixes any problem it lists."
      caption="The verdict is in ~/Library/Application Support/Shipyard/config-status.json, written after every reload."
    >
      {(id) => (
        <>
          <Arrow id={id} d={`M${you.x + you.w} 78H${agent.x}`} />
          <Arrow id={id} d={`M${agent.x + agent.w} 78H${file.x}`} />
          <Arrow id={id} d={`M${mid(file)} ${file.y + file.h}V${app.y}`} />
          <Arrow id={id} d={`M${app.x} 210H${verdict.x + verdict.w}`} />
          <Arrow id={id} folded d={`M${mid(verdict)} ${verdict.y}V${agent.y + agent.h}`} />
          <Label id={id} side="above" x={(you.x + you.w + agent.x) / 2} y={78} text="ASKS" />
          <Label id={id} side="above" x={(agent.x + agent.w + file.x) / 2} y={78} text="EDITS" />
          <Label id={id} side="right" x={mid(file)} y={144} text="SAVED" />
          <Label id={id} side="above" x={(verdict.x + verdict.w + app.x) / 2} y={210} text="WRITES" />
          <Label id={id} side="right" x={mid(verdict)} y={144} text="READS, FIXES" />
          <Node b={you} tag="YOU" name="Ask in words" sub={'"switch to tabs"'} />
          <Node b={agent} tag="AGENT" name="Your agent" sub="/shipyard skill" />
          <Node b={file} tag="FILE" name="Configuration" sub="config.toml" />
          <Node b={verdict} tag="FILE" name="The verdict" sub="config-status.json" />
          <Lines x={you.x} y={186} lines={['The verdict says accepted,', 'with any warnings, or lists', 'each problem with its line.', 'A rejected file changes', 'nothing: the app keeps the', 'last valid configuration.']} />
          <Folded b={app} tag="APP" name="Shipyard.app" sub="rereads on save" />
        </>
      )}
    </Diagram>
  );
}

/* ---------------------------------------------------------------- pings across machines */

/** Where a ping goes from an agent on this Mac or on another machine, to the panel, a notification and its action. */
export function PingsAcrossMachines() {
  const W = 640;
  const H = 532;
  const L = { x: 24, w: 264 };
  const R = { x: 336, w: 264 };
  const zone: Box = { x: 320, y: 24, w: 296, h: 228 };
  const mac = { agent: { ...L, y: 56, h: 68 }, store: { ...L, y: 168, h: 68 } };
  const away = { agent: { ...R, y: 56, h: 68 }, plugin: { ...R, y: 168, h: 68 } };
  const app: Box = { x: 24, y: 292, w: 592, h: 64 };
  const row: Box[] = [0, 1, 2].map((i) => ({ x: 24 + i * 208, y: 404, w: 176, h: 68 }));
  const mid = (b: Box) => b.x + b.w / 2;
  return (
    <Diagram
      slug="pings" w={W} h={H}
      title="Pings across machines"
      desc="An agent on this Mac sends a ping into the ping store, filed by its repository; an agent on another machine sends one into the herdr-shipyard plugin, which keeps it until the Mac asks through Herdr about every 30 seconds. The app lists each ping under its project or its machine's section, notifies, and runs its action when you click it."
      caption="A ping that no project's repository matches lists under its machine's own section, named after the machine's Herdr label."
    >
      {(id) => (
        <>
          <rect x={zone.x} y={zone.y} width={zone.w} height={zone.h} rx="4" className="dg-zone" />
          <Eyebrow x={24} y={44}>THIS MAC</Eyebrow>
          <Eyebrow x={336} y={44}>ANOTHER MACHINE</Eyebrow>
          <Arrow id={id} d={`M${mid(mac.agent)} ${mac.agent.y + mac.agent.h}V${mac.store.y}`} />
          <Arrow id={id} d={`M${mid(away.agent)} ${away.agent.y + away.agent.h}V${away.plugin.y}`} />
          <Arrow id={id} d={`M${mid(mac.store)} ${mac.store.y + mac.store.h}V${app.y}`} />
          <Arrow id={id} dashed d={`M${mid(away.plugin)} ${away.plugin.y + away.plugin.h}V${app.y}`} />
          <Label id={id} side="right" x={mid(mac.store)} y={272} text="WATCHED" />
          <Label id={id} side="right" x={mid(away.plugin)} y={272} text="POLLED · 30 S" />
          <Arrow id={id} d={`M${mid(row[0])} ${app.y + app.h}V${row[0].y}`} />
          <Arrow id={id} d={`M${mid(row[1])} ${app.y + app.h}V${row[1].y}`} />
          <Arrow id={id} d={`M${row[1].x + row[1].w} 438H${row[2].x}`} />
          <Arrow id={id} d={`M${mid(row[0])} ${row[0].y + row[0].h}V484a8 8 0 0 0 8 8H${mid(row[2]) - 8}a8 8 0 0 0 8 -8V${row[2].y + row[2].h}`} />
          <Label id={id} side="below" x={mid(row[1])} y={492} text="CLICK" />
          <Node b={mac.agent} tag="AGENT" name="Your agent" sub="shipyard ping send" />
          <Node b={mac.store} tag="STORE" name="Ping store" sub="filed by its repository" />
          <Node b={away.agent} tag="AGENT" name="Your agent" sub="shipyard ping send" />
          <Node b={away.plugin} tag="PLUGIN" name="herdr-shipyard" sub="keeps it there" />
          <Node b={row[0]} tag="PANEL" name="Listed" sub="needs you until seen" />
          <Node b={row[1]} tag="MACOS" name="Notification" sub="event ping.sent" />
          <Node b={row[2]} tag="ON CLICK" name="Its action" sub="link, app or Herdr tab" />
          <Folded b={app} tag="APP" name="Shipyard.app" sub="lists it under its project, or under the machine's section" nameY={30} />
        </>
      )}
    </Diagram>
  );
}

/** The diagrams a docs section may show, by the name its `diagram` field gives. */
export const DIAGRAMS = { 'how-it-works': HowItWorks, 'config-loop': ConfigLoop, pings: PingsAcrossMachines } as const;
export type DiagramId = keyof typeof DIAGRAMS;
