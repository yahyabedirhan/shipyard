// The docs' figures that never move: a screenshot of the real app. They render to HTML at build time and send no
// JavaScript.
import SHOTS from '../../shots.json';

export interface ShotEntry { id: string; shows: string; state: string; appearance: string; layout: string; path: string }
const BY_ID = Object.fromEntries((SHOTS.shots as ShotEntry[]).map((s) => [s.id, s]));

/** The address a screenshot is served at: the build copies assets/screenshots/launch/ to /shots/. */
export const shotSrc = (id: string) => `/shots/${id}.png`;

/** A screenshot of the real app, by its id in shots.json. */
export function Shot({ id, caption, className, bare }: { id: string; caption?: string; className?: string; bare?: boolean }) {
  const s = BY_ID[id];
  if (!s) throw new Error(`no shot ${id} in shots.json`);
  return (
    <figure className={`fig shot${className ? ` ${className}` : ''}`} data-shot={id}>
      <img src={shotSrc(id)} alt={s.shows} loading="lazy" />
      {!bare ? <figcaption className="cap">{caption ?? s.shows}</figcaption> : null}
    </figure>
  );
}
