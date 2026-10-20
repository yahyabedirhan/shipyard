// The first screen of the landing page, in structurally different variants on one route (`?variant=`). Each says the
// same story in one screen: the one line, the real panel (a Shot placeholder until it's captured), the install
// lines, and the line that tells an agent to use it, then the way to the docs. Small pieces are shared; the
// layouts are not.
import { ASK_AGENT, INSTALL, NAME, RELEASES, REPO } from '../messaging';
import { inlineMd } from '../reference/parse';
import { CodeBlock, CodeTabs } from '../docs/CodeBlocks';
import { RINGS, Shot } from '../docs/figures';
import { FACTS, HOW, WHAT, WHO } from './copy';

export interface VariantProps { line: string }

const INSTALL_TABS = [
  { label: 'From source', lang: 'sh' as const, code: INSTALL.source },
  { label: 'Download', lang: 'sh' as const, code: INSTALL.download },
];

function Install() {
  return <CodeTabs code={INSTALL_TABS} target={(i) => (i === 0 ? 'source' : 'download')} />;
}

function Agent() {
  return (
    <div className="l-agent">
      <CodeBlock code={INSTALL.skill} lang="sh" target="skill" />
      <p>Then tell your agent: <q>{ASK_AGENT}</q></p>
    </div>
  );
}

function Paths() {
  return (
    <nav className="l-paths" aria-label="Next">
      <a className="l-btn" href="/docs">Read the docs</a>
      <a className="l-btn quiet" href="/docs#install">Install</a>
      <a className="l-link" href={RELEASES} target="_blank" rel="noreferrer">Latest release</a>
      <a className="l-link" href={REPO} target="_blank" rel="noreferrer">GitHub</a>
    </nav>
  );
}

const Facts = ({ className = 'l-facts' }: { className?: string }) => (
  <dl className={className}>
    {FACTS.map(([k, v]) => <div key={k}><dt>{k}</dt><dd dangerouslySetInnerHTML={{ __html: inlineMd(v) }} /></div>)}
  </dl>
);

/** A: one quiet column, read top to bottom, like the docs' opening. */
export function VariantA({ line }: VariantProps) {
  return (
    <div className="land va">
      <header className="va-head"><span className="l-mark">{RINGS.A}</span><span className="wordmark">{NAME}</span></header>
      <h1 className="va-line">{line}</h1>
      <div className="va-prose">
        <p>{WHAT}</p>
        <p>{WHO}</p>
        <p>{HOW}</p>
      </div>
      {/* SHOT:readme-hero-dark */}
      <Shot id="readme-hero-dark" className="va-shot" />
      <div className="va-steps">
        <div><span className="l-step">1</span><b>Install the app</b><Install /></div>
        <div><span className="l-step">2</span><b>Give your agents the skill</b><Agent /></div>
      </div>
      <Facts />
      <Paths />
    </div>
  );
}

/** B: the menu bar across the top, the panel hanging from it, the story beside it. */
export function VariantB({ line }: VariantProps) {
  return (
    <div className="land vb">
      <div className="vb-strip" aria-hidden="true">
        <span className="vb-apple" />
        <span className="vb-spacer" />
        <span className="vb-item">{RINGS.A}<b>5</b></span>
        <span className="vb-clock">Tue 09:41</span>
      </div>
      <div className="vb-grid">
        <div className="vb-text">
          <span className="wordmark">{NAME}</span>
          <h1 className="vb-line">{line}</h1>
          <p className="vb-what">{WHAT}</p>
          <p className="vb-who">{WHO}</p>
          <Install />
          <Agent />
          <Paths />
        </div>
        <div className="vb-hang">
          <span className="vb-caret" aria-hidden="true" />
          {/* SHOT:readme-hero-dark */}
          <Shot id="readme-hero-dark" className="vb-shot" />
          <Facts className="l-facts row" />
        </div>
      </div>
    </div>
  );
}

/** C: the terminal is the page. The three steps as one session, the facts as output. */
export function VariantC({ line }: VariantProps) {
  const lines: [string, string][] = [
    ['$', INSTALL.source.replace(/\n/g, ' && ')],
    ['', '# builds Shipyard.app, copies it to /Applications and opens it in the menu bar'],
    ['$', INSTALL.skill],
    ['', '# teaches your coding agents to edit shipyard\'s file'],
    ['>', ASK_AGENT],
    ['', '# your agent adds the repository to config.toml, checks it, and shipyard applies it'],
  ];
  return (
    <div className="land vc">
      <div className="vc-top">
        <span className="wordmark">{NAME}</span>
        <h1 className="vc-line">{line}</h1>
        <p className="vc-who">{WHO}</p>
      </div>
      <div className="vc-grid">
        <figure className="vc-term" aria-label="Install shipyard and the skill, then ask your agent">
          <div className="vc-bar" aria-hidden="true"><i /><i /><i /><span>~ zsh</span></div>
          <pre>{lines.map(([p, t], i) => <div key={i} className={p ? 'in' : 'out'}>{p ? <span className="vc-p">{p}</span> : null}{t}</div>)}</pre>
          <figcaption className="cap">The three steps. The last one is said to your agent, in your words.</figcaption>
        </figure>
        <div className="vc-side">
          {/* SHOT:readme-hero-dark */}
          <Shot id="readme-hero-dark" className="vc-shot" />
          <Facts className="l-facts mono" />
        </div>
      </div>
      <div className="vc-copy">
        <div><span className="inst-t">The app</span><Install /></div>
        <div><span className="inst-t">The skill</span><Agent /></div>
      </div>
      <Paths />
    </div>
  );
}

/** D: an artistic opening. Swells across the screen, the wordmark set large, three short columns, the panel rising. */
export function VariantD({ line }: VariantProps) {
  return (
    <div className="land vd">
      <svg className="vd-sea" viewBox="0 0 1200 400" preserveAspectRatio="none" aria-hidden="true">
        {Array.from({ length: 9 }, (_, i) => (
          <path key={i} d={`M0 ${120 + i * 30} C 200 ${90 + i * 30}, 400 ${150 + i * 30}, 600 ${120 + i * 30} S 1000 ${90 + i * 30}, 1200 ${120 + i * 30}`} style={{ animationDelay: `${-i * 1.3}s`, opacity: 0.25 + i * 0.07 }} />
        ))}
      </svg>
      <div className="vd-inner">
        <span className="vd-word">{NAME}</span>
        <h1 className="vd-line">{line}</h1>
        <div className="vd-cols">
          <div><h2>What</h2><p>{WHAT}</p></div>
          <div><h2>Who</h2><p>{WHO}</p></div>
          <div><h2>How</h2><p>{HOW}</p></div>
        </div>
        <div className="vd-row">
          <div className="vd-install"><Install /><Agent /><Paths /></div>
          {/* SHOT:readme-hero-dark */}
          <Shot id="readme-hero-dark" className="vd-shot" />
        </div>
        <Facts className="l-facts row" />
      </div>
    </div>
  );
}

export const VARIANTS = [
  { id: 'A', name: 'One column', Component: VariantA },
  { id: 'B', name: 'Menu bar', Component: VariantB },
  { id: 'C', name: 'Terminal', Component: VariantC },
  { id: 'D', name: 'Swells', Component: VariantD },
];
