// The landing page at `/`: a prototype on a review branch. Its variants of the first screen sit on this one route,
// switchable with `?variant=A..D` and the floating bar, which a production build leaves out. See README.md here.
import { useEffect, useState } from 'react';
import { Switcher, variantFrom } from '../prototype/Switcher';
import { lineFrom } from './copy';
import { VARIANTS } from './variants';
import '../docs/docs.css';
import './landing.css';

const IDS = VARIANTS.map((v) => v.id);

export function Landing({ search = typeof location === 'undefined' ? '' : location.search }: { search?: string }) {
  const [variant, setVariant] = useState(() => variantFrom(search, IDS));
  const [line, setLine] = useState(() => lineFrom(search, import.meta.env.DEV));
  useEffect(() => { setLine(lineFrom(location.search, import.meta.env.DEV)); }, []);
  const V = VARIANTS.find((v) => v.id === variant) ?? VARIANTS[0];
  return (
    <div className="dx">
      <V.Component line={line} />
      <Switcher variants={VARIANTS} current={variant} onChange={setVariant} />
    </div>
  );
}
