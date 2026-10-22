// The docs' Install section's code: the app's install ways, one tab each with its hint below, and the agent skill.
// It renders to HTML at build time and hydrates as an island; the ways come in as props, so it loads no content.
import { useState } from 'react';
import { track } from '../analytics';
import { CodeBlock, CodeTabs } from './CodeBlocks';
import type { Lang } from './content';

export interface InstallWay { id: string; label: string; lang: Lang; code: string; hint: string }

export function Install({ ways, skill, ask }: { ways: InstallWay[]; skill: string; ask: string }) {
  const [way, setWay] = useState(0);
  return (
    <div className="inst">
      <div>
        <div className="inst-t">The app</div>
        <CodeTabs
          code={ways.map((w) => ({ label: w.label, lang: w.lang, code: w.code }))}
          targets={ways.map((w) => (w.id === 'source' ? 'source' : 'download'))}
          onPick={(i) => { setWay(i); track('install_tab_changed', { to: ways[i].id }); }}
        />
        <p className="inst-hint" dangerouslySetInnerHTML={{ __html: ways[way].hint }} />
      </div>
      <div>
        <div className="inst-t">The agent skill</div>
        <CodeBlock code={skill} lang="sh" target="skill" />
        <p className="inst-hint">Then ask your agent: “{ask}”.</p>
      </div>
    </div>
  );
}
