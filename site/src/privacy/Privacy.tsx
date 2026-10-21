import PRIVACY_HTML from 'virtual:shipyard-privacy';
import { optIn, optOut, analyticsActive } from '../analytics';
import { consent } from '../consent';
import { NAME } from '../messaging';
import { useState } from 'react';
import '../docs/docs.css';
import './privacy.css';

/** A plain page in the docs' style: the wordmark, one column of text, and the way back. */
function Plain({ children }: { children: React.ReactNode }) {
  return (
    <div className="dx">
      <div className="plain">
        <a className="wordmark" href="/"><img src="/logo.png" alt="" width="24" height="24" />{NAME}</a>
        <main id="top">{children}</main>
        <footer className="plain-foot"><a href="/docs">Docs</a><a href="/privacy">Privacy</a><a href="/llms.txt">llms.txt</a></footer>
      </div>
    </div>
  );
}

/** The privacy page, from site/PRIVACY.md, with the opt-out buttons. */
export function Privacy() {
  const [level, setLevel] = useState(() => consent());
  return (
    <Plain>
      <h1 className="title">Privacy</h1>
      <div className="prose" dangerouslySetInnerHTML={{ __html: PRIVACY_HTML }} />
      <div className="optout">
        <p>This browser: <b>{level === 'all' ? 'analytics on' : level === 'pageviews' ? 'pageviews only' : 'nothing sent'}</b>{analyticsActive() || level !== 'all' ? '' : ' (this build has no analytics key, so nothing is sent)'}.</p>
        <div className="optout-btns">
          <button type="button" className="chip" onClick={() => { optOut('pageviews'); setLevel(consent()); }}>Pageviews only</button>
          <button type="button" className="chip" onClick={() => { optOut('none'); setLevel(consent()); }}>Send nothing</button>
          <button type="button" className="chip" onClick={() => { optIn(); setLevel(consent()); }}>Undo</button>
        </div>
      </div>
    </Plain>
  );
}

/** The page for an address that has none. The host serves it as 404.html with a 404 status. */
export function NotFound() {
  return (
    <Plain>
      <h1 className="title">No page here</h1>
      <p className="sub">This address has no page. The <a href="/docs">docs</a> cover install, configuration and the <code>shipyard</code> command, and <a href="/llms.txt">llms.txt</a> has them as plain text.</p>
    </Plain>
  );
}
