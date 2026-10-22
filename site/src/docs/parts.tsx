// The docs page's parts that never move: the generated reference tables, the section extras made of text, the brand
// links and the footer. They render to HTML at build time and send no JavaScript. src/docs/Docs.astro puts them
// together with the islands, and src/docs/Section.astro lays out one section.
import type { ReactNode } from 'react';
import { REF } from '../reference/data';
import type { OutboundTarget } from '../analytics';
import { CHANGELOG, HERDR_PLUGIN, LICENSE, LINE, NAME, PERSONAL_SITE, RELEASES, REPO } from '../messaging';
import { inlineMd, type KeyGroup } from '../reference/parse';
import { LIMITS, QUESTIONS, SECTIONS } from './content';
import { tidy } from './text';

export const pad = (i: number) => String(i + 1).padStart(2, '0');

/** The opening above the first section. */
export const OPENING = {
  head: LINE,
  sub: 'Pull requests, issues, workflow runs and your agents’ pings from the repositories you watch, with one number for what needs you.',
  open1: `${NAME} lists what your agents and other people open on GitHub, grouped into projects you name in one TOML file. You and your agents edit the file, and each save applies at once.`,
  open2: 'Start with <a href="#install">Install</a> and <a href="#first-run">First run</a>, or jump to the <a href="#configuration">configuration reference</a>.',
} as const;

/** HTML from the page's own content, never from input. */
export function Html({ as: Tag = 'span', html, className, id }: { as?: 'span' | 'p' | 'div' | 'dd' | 'dt' | 'td' | 'summary'; html: string; className?: string; id?: string }) {
  return <Tag className={className} id={id} dangerouslySetInnerHTML={{ __html: html }} />;
}

/** Note numbers run through the page; this gives each section the numbers of its notes. */
export const NOTE_NUMBERS: Record<string, number[]> = (() => {
  let n = 0;
  return Object.fromEntries(SECTIONS.map((s) => [s.id, s.notes.map(() => ++n)]));
})();

/** An outbound link that counts its clicks by a fixed target, never by its address: src/boot.ts reads data-out. */
export function Out({ href, target, children }: { href: string; target: OutboundTarget; children: ReactNode }) {
  return <a href={href} target="_blank" rel="noreferrer" data-out={target}>{children}</a>;
}

/* ---------------------------------------------------------------- generated reference */

/** One table of the configuration reference, from the schema. Each row carries its key id for the tests. */
export function KeyTable({ g, prefix = 'keys' }: { g: KeyGroup; prefix?: string }) {
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

export function Flags({ rows, title }: { rows: [string, string][]; title: string }) {
  return (
    <div className="tbl-wrap">
      <table className="tbl">
        <thead><tr><th>{title}</th><th>What it does</th></tr></thead>
        <tbody>{rows.map(([f, w]) => <tr key={f}><Html as="td" html={inlineMd(f)} /><Html as="td" html={tidy(inlineMd(w))} /></tr>)}</tbody>
      </table>
    </div>
  );
}

export function CommandReference() {
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

/** The configuration reference: config.toml's tables, then cli.toml's. */
export function ConfigReference() {
  return (
    <>
      {REF.config.map((g) => <KeyTable key={g.owner} g={g} />)}
      <h3 className="keys-h big">cli.toml</h3>
      <p className="keys-d">The <code>shipyard</code> command reads its own settings file on every machine that runs it: beside <code>config.toml</code> on the Mac, in <code>~/.config/shipyard/</code> elsewhere. Unlike <code>config.toml</code>, an unknown key there is an error.</p>
      {REF.cli.map((g) => <KeyTable key={g.owner} g={g} prefix="cli" />)}
    </>
  );
}

export function Pings() {
  return (
    <>
      <Flags rows={REF.flags.ping} title="ping send" />
      <details className="whole"><summary>Every flag of <code>notice send</code></summary><Flags rows={REF.flags.notice} title="notice send" /></details>
    </>
  );
}

export const Limits = () => <dl className="limits">{LIMITS.map(([t, d]) => <div key={t}><Html as="dt" html={t} /><Html as="dd" html={tidy(d)} /></div>)}</dl>;

export const Questions = () => <div className="faq">{QUESTIONS.map(([q, a]) => <details key={q}><Html as="summary" html={q} /><Html as="p" html={tidy(a)} /></details>)}</div>;

export function Changelog() {
  return REF.changelog ? (
    <dl className="limits">
      <div><dt>Latest release</dt><dd><code>{REF.changelog.version}</code>, {REF.changelog.date}. <Html html={tidy(inlineMd(REF.changelog.summary))} /></dd></div>
      <div><dt>These docs</dt><dd>Describe <code>{REF.version}</code> and what has merged since. <Out href={CHANGELOG} target="changelog">Read the changelog</Out>.</dd></div>
    </dl>
  ) : null;
}

/** One preset's heading, words and facts; Section.astro adds its screenshots and its whole file. */
export function PresetHead({ p }: { p: (typeof REF.presets)[number] }) {
  return (
    <>
      <h3 className="keys-h"><code>{p.id}</code></h3>
      <Html as="p" html={tidy(inlineMd(p.about))} />
      <dl className="pdl"><div><dt>For</dt><Html as="dd" html={inlineMd(p.for)} /></div><div><dt>Asks for</dt><Html as="dd" html={inlineMd(p.asks)} /></div></dl>
    </>
  );
}

/* ---------------------------------------------------------------- the page */

export function BrandLinks() {
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

/** The page's last lines: the coda and the footer's links. */
export function Footer() {
  return (
    <>
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
          <li><a href="/llms.txt" data-astro-reload>llms.txt</a></li>
          <li><a href="/llms-full.txt" data-astro-reload>llms-full.txt</a></li>
          <li><a href="/docs/configuration.md" data-astro-reload>configuration.md</a></li>
        </ul></div>
      </footer>
    </>
  );
}
