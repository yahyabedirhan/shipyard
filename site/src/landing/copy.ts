// The landing page's words. The one line, install lines and links come from messaging.ts; this adds the first
// screen's few sentences: what it is, who it's for, how it's used, and the basic facts. Every variant says the same
// things, so the variants differ only in how they show them.
import { LINES, type LineId } from '../messaging';

export const WHAT = 'Your pull requests, issues and workflow runs, from every repository you watch, in one list in the menu bar. The number beside its icon counts what needs you.';

/** The two uses, as equals, as the messaging kit asks. */
export const WHO = 'For people whose coding agents open pull requests for them, and for maintainers who review what other people open.';

export const HOW = 'Click a row to open it on GitHub. Tell your agent what to show, and it edits the one file shipyard reads. Agents ping you when they need you.';

export const FACTS: [string, string][] = [
  ['Runs on', 'macOS 14 or later'],
  ['Reads', 'github.com, as you'],
  ['Settings', 'one TOML file'],
  ['Command', '`shipyard`, also on Linux'],
  ['License', 'Apache 2.0'],
];

/** In development `?line=A|B|C` shows a candidate one line from the messaging kit; a build shows A. */
export function lineFrom(search: string, dev: boolean): string {
  const q = new URLSearchParams(search).get('line')?.toUpperCase();
  return dev && q && q in LINES ? LINES[q as LineId] : LINES.A;
}
