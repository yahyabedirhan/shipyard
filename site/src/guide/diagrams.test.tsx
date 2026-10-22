// @vitest-environment happy-dom
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { SECTIONS } from './content';
import { DIAGRAMS } from './diagrams';

const svgs = Object.entries(DIAGRAMS).map(([name, D]) => {
  const doc = new DOMParser().parseFromString(renderToStaticMarkup(<D />), 'text/html');
  return { name, svg: doc.querySelector('svg')! };
});

describe('the docs diagrams', () => {
  it('each name themselves to a screen reader by a title and a description', () => {
    for (const { name, svg } of svgs) {
      expect(svg.getAttribute('role'), name).toBe('img');
      const [title, desc] = (svg.getAttribute('aria-labelledby') ?? '').split(' ').map((id) => svg.querySelector(`[id="${id}"]`));
      expect(svg.firstElementChild, name).toBe(title);
      expect(title?.tagName.toLowerCase(), name).toBe('title');
      expect(desc?.tagName.toLowerCase(), name).toBe('desc');
      expect(title?.textContent?.length, name).toBeGreaterThan(0);
      expect(desc?.textContent?.length, name).toBeGreaterThan(40);
    }
  });

  it('keep their ids apart, so two on one page never paint with each other\'s gradients', () => {
    const all = svgs.flatMap(({ svg }) => [...svg.querySelectorAll('[id]')].map((e) => e.id));
    expect(new Set(all).size).toBe(all.length);
    for (const { name, svg } of svgs) {
      const used = [...svg.outerHTML.matchAll(/url\(#([^)]+)\)/g)].map((m) => m[1]);
      for (const id of used) expect(svg.querySelector(`[id="${id}"]`), `${name} ${id}`).not.toBeNull();
    }
  });

  it('are each shown by one section', () => {
    const shown = SECTIONS.flatMap((s) => (s.diagram ? [s.diagram] : []));
    expect(shown.sort()).toEqual(Object.keys(DIAGRAMS).sort());
  });
});
