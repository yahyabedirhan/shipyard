import { useEffect, useState } from 'react';
import { track, type CopyTarget } from '../analytics';
import { highlight } from './code';
import type { Lang, Snippet } from './content';

const COPY = <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true"><rect x="5.5" y="5.5" width="8" height="8" rx="1.6" /><path d="M10.5 3.5v-.4A1.6 1.6 0 0 0 8.9 1.5H3.1A1.6 1.6 0 0 0 1.5 3.1v5.8a1.6 1.6 0 0 0 1.6 1.6h.4" /></svg>;
const CHECK = <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m3 8.5 3 3 7-7" /></svg>;

/** A quiet copy button that turns into a check for a moment. */
export function CopyButton({ text, target = 'code' }: { text: () => string; target?: CopyTarget }) {
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (!done) return;
    const id = window.setTimeout(() => setDone(false), 1200);
    return () => window.clearTimeout(id);
  }, [done]);
  return (
    <button
      type="button"
      className={`copy${done ? ' done' : ''}`}
      aria-label={done ? 'Copied' : 'Copy code'}
      title={done ? 'Copied' : 'Copy code'}
      onClick={async () => {
        try { await navigator.clipboard.writeText(text()); } catch { /* clipboard may be blocked */ }
        setDone(true);
        track('code_copied', { target });
      }}
    >
      {done ? CHECK : COPY}
    </button>
  );
}

/** One block of code, with no title bar: just the code and a copy button in its top-right corner. */
export function CodeBlock({ code, lang, id, target }: { code: string; lang: Lang; id?: string; target?: CopyTarget }) {
  const text = code.trim();
  const one = !text.includes('\n');
  return (
    <figure className={`code${one ? ' one' : ''}`} id={id}>
      <pre><code dangerouslySetInnerHTML={{ __html: highlight(text, lang) }} /></pre>
      {lang === 'text' ? null : <CopyButton text={() => text} target={target} />}
    </figure>
  );
}

/** Several snippets, one tab each. One snippet is a plain block. */
export function CodeTabs({ code, target, onPick }: { code: Snippet[]; target?: (i: number) => CopyTarget; onPick?: (i: number) => void }) {
  const [shown, setShown] = useState(0);
  if (code.length === 1) return <CodeBlock code={code[0].code} lang={code[0].lang} target={target?.(0)} />;
  const s = code[Math.min(shown, code.length - 1)];
  const text = s.code.trim();
  return (
    <figure className="code tabs">
      <div className="code-head">
        <div className="code-tabs" role="tablist" aria-label="Snippet">
          {code.map((c, i) => (
            <button key={c.label ?? i} type="button" className="code-tab" role="tab" aria-selected={i === shown} onClick={() => { setShown(i); onPick?.(i); }}>{c.label ?? c.lang}</button>
          ))}
        </div>
        {s.lang === 'text' ? null : <CopyButton text={() => text} target={target?.(shown)} />}
      </div>
      <pre role="tabpanel" data-lang={s.lang}><code dangerouslySetInnerHTML={{ __html: highlight(text, s.lang) }} /></pre>
    </figure>
  );
}
