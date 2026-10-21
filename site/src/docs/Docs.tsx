import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react';
import { REF } from '../reference/data';
import { track, type OutboundTarget } from '../analytics';
import { ASK_AGENT, CHANGELOG, HERDR_PLUGIN, INSTALL, LICENSE, LINE, NAME, PERSONAL_SITE, RELEASES, REPO } from '../messaging';
import { inlineMd, type KeyGroup } from '../reference/parse';
import { CodeBlock, CodeTabs } from './CodeBlocks';
import { GROUPS, INSTALL_WAYS, LIMITS, QUESTIONS, SECTIONS, byId, type DocSection } from './content';
import { DIAGRAMS } from './diagrams';
import { ConfigExplorer, SAILBOAT, Shot } from './figures';
import { tidy, tidyParagraphs, withMarkers } from './text';
import './docs.css';

const pad = (i: number) => String(i + 1).padStart(2, '0');

/** The opening above the first section. */
export const OPENING = {
  head: LINE,
  sub: 'Pull requests, issues, workflow runs and your agents’ pings from the repositories you watch, with one number for what needs you.',
  open1: `${NAME} lists what your agents and other people open on GitHub, grouped into projects you name in one TOML file. You and your agents edit the file, and each save applies at once.`,
  open2: 'Start with <a href="#install">Install</a> and <a href="#first-run">First run</a>, or jump to the <a href="#configuration">configuration reference</a>.',
} as const;

/** HTML from the page's own content, never from input. */
function Html({ as: Tag = 'span', html, className, id }: { as?: 'span' | 'p' | 'div' | 'dd' | 'dt' | 'td' | 'summary'; html: string; className?: string; id?: string }) {
  return <Tag className={className} id={id} dangerouslySetInnerHTML={{ __html: html }} />;
}

/** Note numbers run through the page; this gives each section the numbers of its notes. */
const NOTE_NUMBERS: Record<string, number[]> = (() => {
  let n = 0;
  return Object.fromEntries(SECTIONS.map((s) => [s.id, s.notes.map(() => ++n)]));
})();

/** An outbound link that counts its clicks by a fixed target, never by its address. */
function Out({ href, target, children }: { href: string; target: OutboundTarget; children: ReactNode }) {
  return <a href={href} target="_blank" rel="noreferrer" onClick={() => track('outbound_clicked', { target })}>{children}</a>;
}

/* ---------------------------------------------------------------- generated reference */

/** One table of the configuration reference, from the schema. Each row carries its key id for the tests. */
function KeyTable({ g, prefix = 'keys' }: { g: KeyGroup; prefix?: string }) {
  return (
    <div className="keys" id={`${prefix}-${g.owner}`}>
      <h3 className="keys-h">{/[[=]/.test(g.heading) ? <code>{g.heading}</code> : g.heading}{g.also ? <span className="also">also {g.also}</span> : null}</h3>
      {g.description ? <p className="keys-d">{g.description}</p> : null}
      <div className="tbl-wrap">
        <table className="tbl">
          <thead><tr><th>Key</th><th>Default</th><th>What it takes</th></tr></thead>
          <tbody>
            {g.rows.map((r) => (
              <tr key={r.id} data-key={r.id} id={`key-${r.id}`}>
                <td><code>{r.key}</code>{r.required ? <span className="req">required</span> : null}</td>
                <td className="num">{r.default ? <code>{r.default}</code> : <span className="none">unset</span>}</td>
                <td>
                  <span className="ty">{r.type}{r.allowed ? <>: <Html html={inlineMd(r.allowed)} /></> : null}</span>
                  {r.table ? <span className="ty"> · <a href={`#${prefix}-${r.table}`}>its keys</a></span> : null}
                  <Html as="p" className="kd" html={tidy(inlineMd(r.description))} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Flags({ rows, title }: { rows: [string, string][]; title: string }) {
  return (
    <div className="tbl-wrap">
      <table className="tbl">
        <thead><tr><th>{title}</th><th>What it does</th></tr></thead>
        <tbody>{rows.map(([f, w]) => <tr key={f}><Html as="td" html={inlineMd(f)} /><Html as="td" html={tidy(inlineMd(w))} /></tr>)}</tbody>
      </table>
    </div>
  );
}

function CommandReference() {
  const c = REF.commands;
  return (
    <>
      {c.sections.map((s) => (
        <div className="keys" key={s.id} id={`cmd-${s.id}`}>
          <h3 className="keys-h">{s.heading}</h3>
          <div className="tbl-wrap">
            <table className="tbl">
              <thead><tr><th>Command</th><th>What it does</th></tr></thead>
              <tbody>{s.commands.map((r) => <tr key={r.usage} data-command={r.usage}><td><code>{r.usage}</code></td><td>{r.summary}</td></tr>)}</tbody>
            </table>
          </div>
        </div>
      ))}
      <div className="keys">
        <h3 className="keys-h">Options and environment</h3>
        <div className="tbl-wrap">
          <table className="tbl">
            <tbody>
              {[...c.options, ...c.environment].map(([k, v]) => <tr key={k}><td><code>{k}</code></td><Html as="td" html={inlineMd(v)} /></tr>)}
            </tbody>
          </table>
        </div>
        <p className="keys-d">{c.exitCodes} On a machine without the app, <code>{c.macOnly.join('</code>, <code>')}</code> exit 2 with a pointer to the Mac.</p>
      </div>
    </>
  );
}

/* ---------------------------------------------------------------- section extras */

function Install() {
  const [way, setWay] = useState(0);
  return (
    <div className="inst">
      <div>
        <div className="inst-t">The app</div>
        <CodeTabs
          code={INSTALL_WAYS.map((w) => ({ label: w.label, lang: w.lang, code: w.code }))}
          target={(i) => (INSTALL_WAYS[i].id === 'source' ? 'source' : 'download')}
          onPick={(i) => { setWay(i); track('install_tab_changed', { to: INSTALL_WAYS[i].id }); }}
        />
        <Html as="p" className="inst-hint" html={INSTALL_WAYS[way].hint} />
      </div>
      <div>
        <div className="inst-t">The agent skill</div>
        <CodeBlock code={INSTALL.skill} lang="sh" target="skill" />
        <p className="inst-hint">Then ask your agent: “{ASK_AGENT}”.</p>
      </div>
    </div>
  );
}

function Presets() {
  return (
    <div className="presets">
      {REF.presets.map((p) => (
        <div className="preset" key={p.id} id={`preset-${p.id}`}>
          <h3 className="keys-h"><code>{p.id}</code></h3>
          <Html as="p" html={tidy(inlineMd(p.about))} />
          <dl className="pdl"><div><dt>For</dt><Html as="dd" html={inlineMd(p.for)} /></div><div><dt>Asks for</dt><Html as="dd" html={inlineMd(p.asks)} /></div></dl>
          <div className="shot-pair"><Shot id={`preset-${p.id}-dark`} /><Shot id={`preset-${p.id}-light`} /></div>
          <details className="whole"><summary><code>{p.id}</code> <span aria-hidden="true">›</span> <code>config.toml</code></summary><CodeBlock code={p.file} lang="toml" target="config" /></details>
        </div>
      ))}
    </div>
  );
}

function Extras({ s }: { s: DocSection }) {
  switch (s.extra) {
    case 'install': return <Install />;
    case 'presets': return <Presets />;
    case 'explorer': return <ConfigExplorer />;
    case 'pings': return (
      <>
        <Flags rows={REF.flags.ping} title="ping send" />
        <details className="whole"><summary>Every flag of <code>notice send</code></summary><Flags rows={REF.flags.notice} title="notice send" /></details>
      </>
    );
    case 'config': return (
      <>
        {REF.config.map((g) => <KeyTable key={g.owner} g={g} />)}
        <h3 className="keys-h big">cli.toml</h3>
        <p className="keys-d">The <code>shipyard</code> command reads its own settings file on every machine that runs it: beside <code>config.toml</code> on the Mac, in <code>~/.config/shipyard/</code> elsewhere. Unlike <code>config.toml</code>, an unknown key there is an error.</p>
        {REF.cli.map((g) => <KeyTable key={g.owner} g={g} prefix="cli" />)}
      </>
    );
    case 'commands': return <CommandReference />;
    case 'limits': return <dl className="limits">{LIMITS.map(([t, d]) => <div key={t}><Html as="dt" html={t} /><Html as="dd" html={tidy(d)} /></div>)}</dl>;
    case 'troubleshooting': return <div className="faq">{QUESTIONS.map(([q, a]) => <details key={q}><Html as="summary" html={q} /><Html as="p" html={tidy(a)} /></details>)}</div>;
    case 'changelog': return REF.changelog ? (
      <dl className="limits">
        <div><dt>Latest release</dt><dd><code>{REF.changelog.version}</code>, {REF.changelog.date}. <Html html={tidy(inlineMd(REF.changelog.summary))} /></dd></div>
        <div><dt>These docs</dt><dd>Describe <code>{REF.version}</code> and what has merged since. <Out href={CHANGELOG} target="changelog">Read the changelog</Out>.</dd></div>
      </dl>
    ) : null;
    default: return null;
  }
}

/* ---------------------------------------------------------------- sections */

function Section({ s, index }: { s: DocSection; index: number }) {
  const numbers = NOTE_NUMBERS[s.id];
  const Figure = s.diagram ? DIAGRAMS[s.diagram] : null;
  return (
    <section className="sec" id={s.id} aria-labelledby={`h-${s.id}`}>
      <h2 className="sec-h" id={`h-${s.id}`}><a href={`#${s.id}`}>{s.title}</a><span className="n">{pad(index)}</span></h2>
      <Html as="p" className="lede" html={tidy(s.lede)} />
      {s.body ? <Html as="div" className="body" html={tidyParagraphs(withMarkers(s.body, numbers))} /> : null}
      {Figure ? <Figure /> : null}
      {s.extra === 'install' ? <Extras s={s} /> : null}
      {s.code && !s.codeLast ? <CodeTabs code={s.code} target={(i) => (s.code![i].lang === 'toml' ? 'config' : 'command')} /> : null}
      {s.shots ? <div className="shot-pair">{s.shots.map((id) => <Shot key={id} id={id} />)}</div> : null}
      {s.extra && s.extra !== 'install' ? <Extras s={s} /> : null}
      {s.after ? <Html as="div" className="body after" html={tidyParagraphs(s.after)} /> : null}
      {s.code && s.codeLast ? <CodeTabs code={s.code} target={() => 'command'} /> : null}
      <aside className="mar">
        {s.notes.map((n, j) => (
          <p className="sn" key={numbers[j]} id={`fn-${numbers[j]}`} data-ref={`fnref-${numbers[j]}`}>
            <span className="k">{numbers[j]}</span><Html html={tidy(n)} />
          </p>
        ))}
      </aside>
    </section>
  );
}

/* ---------------------------------------------------------------- the page */

function BrandLinks() {
  const rows: [string, string, OutboundTarget | null][][] = [
    [['GitHub', REPO, 'github'], ['releases', RELEASES, 'releases']],
    [['yahyapak.dev', PERSONAL_SITE, 'site']],
  ];
  return (
    <div className="blinks-rows">
      {rows.map((row, i) => (
        <ul className="blinks" key={i}>
          {row.map(([label, href, out]) => <li key={label}>{out ? <Out href={href} target={out}>{label}</Out> : <a href={href}>{label}</a>}</li>)}
        </ul>
      ))}
    </div>
  );
}

const WIDE = '(min-width: 1041px)';

/** Lines each margin note up with its marker, below the note above it. */
function placeNotes(main: HTMLElement) {
  const wide = matchMedia(WIDE).matches;
  for (const sec of main.querySelectorAll<HTMLElement>('.sec')) {
    const notes = sec.querySelectorAll<HTMLElement>('.sn');
    if (!wide) { notes.forEach((n) => { n.style.top = ''; }); continue; }
    const base = sec.getBoundingClientRect().top;
    let floor = -Infinity;
    for (const n of notes) {
      const ref = document.getElementById(n.dataset.ref ?? '');
      const top = Math.max(ref ? ref.getBoundingClientRect().top - base - 3 : 110, floor);
      n.style.top = `${top}px`;
      floor = top + n.offsetHeight + 14;
    }
  }
}

/** The docs page: one column of numbered sections, the nav on the left and notes in the margin. */
export function Docs({ home = '/' }: { home?: string }) {
  const main = useRef<HTMLElement>(null);
  const navlist = useRef<HTMLUListElement>(null);
  const ring = useRef<HTMLDivElement>(null);
  const [current, setCurrent] = useState(SECTIONS[0].id);

  // Margin notes follow their markers as screenshots load and the window resizes.
  useEffect(() => {
    const el = main.current;
    if (!el) return;
    let raf = 0;
    const again = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(() => placeNotes(el)); };
    again();
    void document.fonts?.ready.then(again);
    const ro = new ResizeObserver(again);
    ro.observe(el);
    addEventListener('resize', again);
    const late = window.setTimeout(again, 1200);
    return () => { cancelAnimationFrame(raf); ro.disconnect(); removeEventListener('resize', again); window.clearTimeout(late); };
  }, []);

  // The nav marks the section being read; the ring moves to it.
  useEffect(() => {
    let raf = 0;
    const spy = () => {
      const y = innerHeight * 0.3;
      let id = SECTIONS[0].id;
      for (const s of SECTIONS) if ((document.getElementById(s.id)?.getBoundingClientRect().top ?? Infinity) < y) id = s.id;
      if (scrollY < 200) id = SECTIONS[0].id;
      setCurrent(id);
    };
    const onScroll = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(spy); };
    spy();
    addEventListener('scroll', onScroll, { passive: true });
    return () => { cancelAnimationFrame(raf); removeEventListener('scroll', onScroll); };
  }, []);
  useEffect(() => {
    const a = navlist.current?.querySelector<HTMLElement>(`a[data-id="${current}"]`);
    const r = ring.current;
    if (!r) return;
    if (!a) { r.style.opacity = '0'; return; }
    r.style.opacity = '';
    r.style.transform = `translateY(${a.offsetTop + a.offsetHeight / 2 - 12}px)`;
    r.classList.remove('moving');
    void r.offsetWidth;
    r.classList.add('moving');
  }, [current]);

  useEffect(() => {
    const id = decodeURIComponent(location.hash.slice(1));
    if (id) document.getElementById(id)?.scrollIntoView();
  }, []);

  // On a wide screen a note marker flashes its note in the margin instead of jumping to it.
  const onClick = (e: MouseEvent) => {
    const a = (e.target as HTMLElement).closest<HTMLAnchorElement>('sup.fn a');
    if (!a || !matchMedia(WIDE).matches) return;
    const note = document.querySelector<HTMLElement>(a.getAttribute('href')!);
    if (!note) return;
    e.preventDefault();
    note.classList.remove('flash');
    void note.offsetWidth;
    note.classList.add('flash');
    window.setTimeout(() => note.classList.remove('flash'), 900);
  };

  return (
    <div className="dx">
      <div className="mbar">
        <a className="wordmark" href={home}><img src="/logo.png" alt="" width="24" height="24" />{NAME}</a>
        <select aria-label="Jump to section" value={current} onChange={(e) => document.getElementById(e.target.value)?.scrollIntoView()}>
          {SECTIONS.map((s, i) => <option key={s.id} value={s.id}>{pad(i)} {s.nav}</option>)}
        </select>
      </div>
      <div className="page">
        <nav className="nav" aria-label="Docs">
          <div className="brand">
            <a className="wordmark" href={home}><img src="/logo.png" alt="" width="24" height="24" />{NAME}</a>
            <BrandLinks />
            {REF.version ? <span className="ver" title="The version these docs describe">{REF.version}</span> : null}
          </div>
          <div className="secs">
            <div className="ring" ref={ring} aria-hidden="true">{SAILBOAT}</div>
            <ul ref={navlist}>
              {GROUPS.map((g) => [
                <li className="grp" key={`g-${g.name}`} aria-hidden="true" />,
                ...g.ids.map((id) => <li key={id}><a href={`#${id}`} data-id={id} className={id === current ? 'on' : undefined}>{byId[id].nav}</a></li>),
              ])}
            </ul>
          </div>
          <a className="nav-foot" href="#install" data-id="install">Install shipyard</a>
        </nav>
        <main id="top" ref={main} onClick={onClick}>
          <div className="head"><BrandLinks /></div>
          <h1 className="title">{OPENING.head}</h1>
          <p className="sub">{OPENING.sub}</p>
          <div className="shot-pair hero-pair">
            {/* SHOT:landing-tabs-dark */}
            <Shot id="landing-tabs-dark" bare />
            {/* SHOT:landing-list-light */}
            <Shot id="landing-list-light" bare />
          </div>
          <div className="intro">
            <Html as="p" html={tidy(OPENING.open1)} />
            <Html as="p" html={tidy(OPENING.open2)} />
          </div>
          {SECTIONS.map((s, i) => <Section key={s.id} s={s} index={i} />)}
          <p className="coda"><span className="wm-inline">{NAME}</span> is open source under Apache 2.0. Ideas and bugs are welcome in <Out href={`${REPO}/issues`} target="github">its issues</Out>.</p>
          <footer className="foot">
            <div><h3>Project</h3><ul>
              <li><Out href={REPO} target="github">GitHub</Out></li>
              <li><Out href={RELEASES} target="releases">Latest release</Out></li>
              <li><Out href={CHANGELOG} target="changelog">Changelog</Out></li>
              <li><Out href={HERDR_PLUGIN} target="herdr-plugin">herdr-shipyard</Out></li>
            </ul></div>
            <div><h3>License</h3><ul>
              <li><Out href={LICENSE} target="github">Apache 2.0</Out></li>
              <li><a href="/privacy">Privacy</a></li>
              <li><Out href={PERSONAL_SITE} target="site">yahyapak.dev</Out></li>
            </ul></div>
            <div><h3>For agents</h3><ul>
              <li><a href="/llms.txt">llms.txt</a></li>
              <li><a href="/llms-full.txt">llms-full.txt</a></li>
              <li><a href="/docs/configuration.md">configuration.md</a></li>
            </ul></div>
          </footer>
        </main>
      </div>
    </div>
  );
}
