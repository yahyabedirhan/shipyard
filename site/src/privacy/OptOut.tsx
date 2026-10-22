// The privacy page's opt-out buttons and the choice this browser has made. It renders to HTML at build time and
// hydrates as an island; the saved choice lives in this browser, so it is read once the island runs.
import { useEffect, useState } from 'react';
import { analyticsActive, optIn, optOut } from '../analytics';
import { consent, type Consent } from '../consent';

export function OptOut() {
  const [level, setLevel] = useState<Consent>('all');
  useEffect(() => { setLevel(consent()); }, []);
  return (
    <div className="optout">
      <p>This browser: <b>{level === 'all' ? 'analytics on' : level === 'pageviews' ? 'pageviews only' : 'nothing sent'}</b>{analyticsActive() || level !== 'all' ? '' : ' (this build has no analytics key, so nothing is sent)'}.</p>
      <div className="optout-btns">
        <button type="button" className="chip" onClick={() => { optOut('pageviews'); setLevel(consent()); }}>Pageviews only</button>
        <button type="button" className="chip" onClick={() => { optOut('none'); setLevel(consent()); }}>Send nothing</button>
        <button type="button" className="chip" onClick={() => { optIn(); setLevel(consent()); }}>Undo</button>
      </div>
    </div>
  );
}
