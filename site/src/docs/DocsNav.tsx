// The docs nav's moving parts, each an island: the section list with the mark that glides to the section being read,
// and the phone bar's jump menu. Both render to HTML at build time with the first section marked, so the nav works
// as plain links without JavaScript. Their props are plain data, so the islands never load the docs' content.
import { useEffect, useRef, useState } from 'react';
import { SAILBOAT } from './sailboat';

export interface NavSection { id: string; nav: string }

/** The section being read: the last one whose top has passed 30% of the window, and the first near the top. */
function useCurrentSection(ids: string[]): string {
  const [current, setCurrent] = useState(ids[0]);
  useEffect(() => {
    let raf = 0;
    const spy = () => {
      const y = innerHeight * 0.3;
      let id = ids[0];
      for (const s of ids) if ((document.getElementById(s)?.getBoundingClientRect().top ?? Infinity) < y) id = s;
      if (scrollY < 200) id = ids[0];
      setCurrent(id);
    };
    const onScroll = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(spy); };
    spy();
    addEventListener('scroll', onScroll, { passive: true });
    return () => { cancelAnimationFrame(raf); removeEventListener('scroll', onScroll); };
  }, [ids]);
  return current;
}

/** The nav's sections in their groups, in page order `order`; the ring moves to the section being read. */
export function NavSections({ groups, order }: { groups: NavSection[][]; order: string[] }) {
  const navlist = useRef<HTMLUListElement>(null);
  const ring = useRef<HTMLDivElement>(null);
  const current = useCurrentSection(order);
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
  return (
    <div className="secs">
      <div className="ring" ref={ring} aria-hidden="true">{SAILBOAT}</div>
      <ul ref={navlist}>
        {groups.map((g, i) => [
          <li className="grp" key={`g-${i}`} aria-hidden="true" />,
          ...g.map((s) => <li key={s.id}><a href={`#${s.id}`} data-id={s.id} className={s.id === current ? 'on' : undefined}>{s.nav}</a></li>),
        ])}
      </ul>
    </div>
  );
}

/** The phone bar's menu of sections, numbered in page order, showing the section being read. */
export function JumpMenu({ sections }: { sections: NavSection[] }) {
  const ids = useRef(sections.map((s) => s.id)).current;
  const current = useCurrentSection(ids);
  return (
    <select aria-label="Jump to section" value={current} onChange={(e) => document.getElementById(e.target.value)?.scrollIntoView()}>
      {sections.map((s, i) => <option key={s.id} value={s.id}>{String(i + 1).padStart(2, '0')} {s.nav}</option>)}
    </select>
  );
}
