import { describe, expect, it } from 'vitest';
import { openPlaceholders } from './placeholders.mjs';

describe('npm run placeholders', () => {
  const open = openPlaceholders();

  it('lists the screenshots still marked placeholder', () => {
    expect(open.some((o) => o.kind === 'shot' && o.what.startsWith('readme-hero-light:'))).toBe(true);
  });

  it('lists PLACEHOLDER: markers with their file and line', () => {
    expect(open.some((o) => o.kind === 'marker' && /^site\/src\/messaging\.ts:\d+$/.test(o.where))).toBe(true);
  });

  it('lists SHOT: markers whose shot is not done', () => {
    expect(open.some((o) => o.what === 'SHOT:readme-hero-dark is still a placeholder')).toBe(true);
  });
});
