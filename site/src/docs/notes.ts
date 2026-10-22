// The docs' margin notes, in the browser. On a wide screen each note lines up with its marker, below the note above
// it, and follows it as screenshots load and the window resizes; a marker flashes its note instead of jumping to it.
// It starts on every page load, the client router's included, and stops before the router swaps the page.

const WIDE = '(min-width: 1041px)';

/** Lines each margin note up with its marker, below the note above it. */
function placeNotes(main: HTMLElement) {
  const wide = matchMedia(WIDE).matches;
  for (const sec of main.querySelectorAll<HTMLElement>('.sec')) {
    const notes = sec.querySelectorAll<HTMLElement>('.sn');
    if (!wide) { notes.forEach((n) => { n.style.top = ''; }); continue; }
    const base = sec.getBoundingClientRect().top;
    let floor = -Infinity;
    for (const n of notes) {
      const ref = document.getElementById(n.dataset.ref ?? '');
      const top = Math.max(ref ? ref.getBoundingClientRect().top - base - 3 : 110, floor);
      n.style.top = `${top}px`;
      floor = top + n.offsetHeight + 14;
    }
  }
}

let teardown: (() => void) | null = null;

function start() {
  teardown?.();
  teardown = null;
  const el = document.querySelector<HTMLElement>('.dx .page > main');
  if (!el?.querySelector('.sec')) return;
  let raf = 0;
  const again = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(() => placeNotes(el)); };
  again();
  void document.fonts?.ready.then(again);
  const ro = new ResizeObserver(again);
  ro.observe(el);
  addEventListener('resize', again);
  const late = window.setTimeout(again, 1200);
  teardown = () => { cancelAnimationFrame(raf); ro.disconnect(); removeEventListener('resize', again); window.clearTimeout(late); };
}

document.addEventListener('astro:page-load', start);
document.addEventListener('astro:before-swap', () => { teardown?.(); teardown = null; });

// On a wide screen a note marker flashes its note in the margin instead of jumping to it. It listens in the capture
// phase, so it runs before the client router would take the click as a navigation.
document.addEventListener('click', (e) => {
  const a = (e.target as Element | null)?.closest?.<HTMLAnchorElement>('.dx main sup.fn a');
  if (!a || !matchMedia(WIDE).matches) return;
  const note = document.querySelector<HTMLElement>(a.getAttribute('href')!);
  if (!note) return;
  e.preventDefault();
  note.classList.remove('flash');
  void note.offsetWidth;
  note.classList.add('flash');
  window.setTimeout(() => note.classList.remove('flash'), 900);
}, true);
