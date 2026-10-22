// The docs' figures that never move: a screenshot of the real app, or its placeholder frame. They render to HTML at
// build time and send no JavaScript.
import SHOTS from '../../shots.json';

export interface ShotEntry { id: string; shows: string; state: string; appearance: string; layout: string; path: string; status: 'placeholder' | 'done' }
const BY_ID = Object.fromEntries((SHOTS.shots as ShotEntry[]).map((s) => [s.id, s]));

/** The address a finished screenshot is served at: the build copies assets/screenshots/launch/ to /shots/. */
export const shotSrc = (id: string) => `/shots/${id}.png`;

/**
 * A screenshot of the real app, by its id in shots.json. Until its status is done, it shows a placeholder frame
 * with what the picture must show, so a page never claims a picture it doesn't have.
 */
export function Shot({ id, caption, className, bare }: { id: string; caption?: string; className?: string; bare?: boolean }) {
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
      {!bare && (caption || s.status === 'done') ? <figcaption className="cap">{caption ?? s.shows}</figcaption> : null}
    </figure>
  );
}
