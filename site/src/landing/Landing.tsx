// The landing page at `/`: the wordmark set large over slow swells, what shipyard is, who it is for and how it is
// used in three columns, the install lines beside the real panel, then the facts. See README.md here.
import { ASK_AGENT, INSTALL, LINE, NAME, RELEASES, REPO } from '../messaging';
import { inlineMd } from '../reference/parse';
import { CodeBlock, CodeTabs } from '../docs/CodeBlocks';
import { Shot } from '../docs/figures';
import { FACTS, HOW, WHAT, WHO } from './copy';
import '../docs/docs.css';
import './landing.css';

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

export function Landing() {
  return (
    <div className="dx">
    <div className="land vd">
      <svg className="vd-sea" viewBox="0 0 1200 400" preserveAspectRatio="none" aria-hidden="true">
        {Array.from({ length: 9 }, (_, i) => (
          <path key={i} d={`M0 ${120 + i * 30} C 200 ${90 + i * 30}, 400 ${150 + i * 30}, 600 ${120 + i * 30} S 1000 ${90 + i * 30}, 1200 ${120 + i * 30}`} style={{ animationDelay: `${-i * 1.3}s`, opacity: 0.25 + i * 0.07 }} />
        ))}
      </svg>
      <div className="vd-inner">
        <span className="vd-word">{NAME}</span>
        <h1 className="vd-line">{LINE}</h1>
        <div className="vd-cols">
          <div><h2>What</h2><p>{WHAT}</p></div>
          <div><h2>Who</h2><p>{WHO}</p></div>
          <div><h2>How</h2><p>{HOW}</p></div>
        </div>
        <div className="vd-row">
          <div className="vd-install"><Install /><Agent /><Paths /></div>
          <div className="vd-shots">
            {/* SHOT:landing-tabs-dark */}
            <Shot id="landing-tabs-dark" className="vd-shot" bare />
            {/* SHOT:landing-list-light */}
            <Shot id="landing-list-light" className="vd-shot" bare />
          </div>
        </div>
        <Facts className="l-facts row" />
      </div>
    </div>
    </div>
  );
}

