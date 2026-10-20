import { useEffect } from 'react';
import './switcher.css';

export interface VariantInfo { id: string; name: string }

/** The variant after (or before) `current`, wrapping around. */
export function cycle(ids: string[], current: string, step: 1 | -1): string {
  const i = Math.max(0, ids.indexOf(current));
  return ids[(i + step + ids.length) % ids.length];
}

/** The variant a query string asks for, or the first. */
export function variantFrom(search: string, ids: string[]): string {
  const v = new URLSearchParams(search).get('variant')?.toUpperCase();
  return v && ids.includes(v) ? v : ids[0];
}

const typing = (el: Element | null) => el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement || (el instanceof HTMLElement && el.isContentEditable);

/**
 * The prototype's floating bar: the previous and next arrows and the current variant's name. The arrows and the
 * ← and → keys move through the variants and keep the choice in `?variant=`, so a link opens the same one.
 * It renders nothing in a production build, so a stray merge can't ship it.
 */
export function Switcher({ variants, current, onChange, production = import.meta.env.PROD }: { variants: VariantInfo[]; current: string; onChange: (id: string) => void; production?: boolean }) {
  const ids = variants.map((v) => v.id);
  const go = (step: 1 | -1) => {
    const next = cycle(ids, current, step);
    const url = new URL(location.href);
    url.searchParams.set('variant', next);
    history.replaceState(history.state, '', url.pathname + url.search + url.hash);
    onChange(next);
  };
  useEffect(() => {
    if (production) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || typing(document.activeElement)) return;
      if (e.key === 'ArrowLeft') go(-1);
      else if (e.key === 'ArrowRight') go(1);
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  });
  if (production) return null;
  const v = variants.find((x) => x.id === current) ?? variants[0];
  return (
    <div className="proto-switcher" role="toolbar" aria-label="Prototype variants">
      <button type="button" aria-label="Previous variant" onClick={() => go(-1)}>←</button>
      <span className="proto-label"><b>{v.id}</b> {v.name}</span>
      <button type="button" aria-label="Next variant" onClick={() => go(1)}>→</button>
    </div>
  );
}
