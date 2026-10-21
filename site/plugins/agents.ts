// The site's plain-text surfaces for AI agents, made from the same content as the docs page: llms.txt, llms-full.txt
// and one Markdown page per docs section under /docs/, the configuration and command references included.
import { INSTALL_WAYS, LIMITS, QUESTIONS, SECTIONS, type DocSection } from '../src/docs/content';
import { ASK_AGENT, CATEGORY, CHANGELOG, HERDR_PLUGIN, INSTALL, LINE, NAME, PROOF, RELEASES, REPO, SITE_URL } from '../src/messaging';
import { htmlToMd } from '../src/reference/markdown';
import type { KeyGroup } from '../src/reference/parse';
import type { ReferenceData } from './repo';

const md = (html: string) => htmlToMd(html, SITE_URL);
const cell = (s: string) => s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
const fence = (lang: string, code: string) => `\`\`\`${lang === 'text' ? '' : lang}\n${code.trim()}\n\`\`\``;

function keyTable(g: KeyGroup): string {
  const rows = g.rows.map((r) => `| \`${r.key}\`${r.required ? ' (required)' : ''} | ${r.default ? `\`${cell(r.default)}\`` : 'unset'} | ${cell([r.type, r.allowed].filter(Boolean).join(': '))} | ${cell(r.description)} |`);
  return [`### \`${g.heading}\`${g.also ? ` (also ${g.also})` : ''}`, '', g.description, '', '| Key | Default | Type | What it does |', '|---|---|---|---|', ...rows].join('\n');
}

function extra(s: DocSection, ref: ReferenceData): string {
  switch (s.extra) {
    case 'install': return [...INSTALL_WAYS.map((w) => `### ${w.label}\n\n${md(w.hint)}\n\n${fence(w.lang, w.code)}`), `### The agent skill\n\n${fence('sh', INSTALL.skill)}\n\nThen ask your agent: "${ASK_AGENT}".`].join('\n\n');
    case 'presets': return ref.presets.map((p) => `### \`${p.id}\`\n\n${p.about}\n\n- For: ${p.for}\n- Asks for: ${p.asks}\n\n${fence('toml', p.file)}`).join('\n\n');
    case 'explorer': return 'The page shows a mock panel for a few snippets. The keys they set are in [configuration.md](configuration.md).';
    case 'pings': return [`### \`shipyard ping send\` flags`, '', '| Flag | What it does |', '|---|---|', ...ref.flags.ping.map(([f, w]) => `| ${cell(f)} | ${cell(w)} |`), '', `### \`shipyard notice send\` flags`, '', '| Flag | What it does |', '|---|---|', ...ref.flags.notice.map(([f, w]) => `| ${cell(f)} | ${cell(w)} |`)].join('\n');
    case 'config': return [...ref.config.map(keyTable), '## cli.toml', '', 'The `shipyard` command reads its own settings file on every machine that runs it. An unknown key there is an error.', ...ref.cli.map(keyTable)].join('\n\n');
    case 'commands': return [
      ...ref.commands.sections.map((sec) => [`### ${sec.heading}`, '', '| Command | What it does |', '|---|---|', ...sec.commands.map((c) => `| \`${cell(c.usage)}\` | ${cell(c.summary)} |`)].join('\n')),
      ['### Options and environment', '', ...[...ref.commands.options, ...ref.commands.environment].map(([k, v]) => `- \`${k}\`: ${v}`), '', ref.commands.exitCodes].join('\n'),
    ].join('\n\n');
    case 'limits': return LIMITS.map(([t, d]) => `- **${md(t)}:** ${md(d)}`).join('\n');
    case 'troubleshooting': return QUESTIONS.map(([q, a]) => `### ${md(q)}\n\n${md(a)}`).join('\n\n');
    case 'changelog': return ref.changelog ? `Latest release: ${ref.changelog.version} (${ref.changelog.date}). ${ref.changelog.summary}` : '';
    default: return '';
  }
}

/** One docs section as a Markdown page. */
export function sectionMd(s: DocSection, ref: ReferenceData): string {
  return [
    `# ${s.title}`,
    md(s.lede),
    s.body ? md(s.body) : '',
    s.code && !s.codeLast ? s.code.map((c) => fence(c.lang, c.code)).join('\n\n') : '',
    extra(s, ref),
    s.after ? md(s.after) : '',
    s.code && s.codeLast ? s.code.map((c) => fence(c.lang, c.code)).join('\n\n') : '',
    s.notes.length ? `Notes:\n\n${s.notes.map((n) => `- ${md(n)}`).join('\n')}` : '',
  ].filter(Boolean).join('\n\n');
}

export const pagePath = (s: DocSection) => `docs/${s.id}.md`;

function llmsTxt(ref: ReferenceData): string {
  return `# ${NAME}

> ${LINE} ${PROOF}

${CATEGORY} It lists the pull requests, issues and workflow runs of the GitHub repositories you watch, grouped into projects, with one number in the menu bar for what needs attention, and your agents' pings. Everything it shows is set in one TOML file, \`~/.config/shipyard/config.toml\`, that you and your agents edit. These docs describe version ${ref.version}.

## For AI agents

- To change someone's shipyard, edit their \`config.toml\` with the agent skill: \`${INSTALL.skill}\`. The skill knows every key, checks each edit and reads the app's verdict.
- To tell the user something, use the \`shipyard\` command on their machine: \`shipyard ping send "<title>"\` for what they must act on, \`shipyard notice send "<title>"\` for a status that needs nothing from them.
- Never invent a key: every key is in [docs/configuration.md](${SITE_URL}/docs/configuration.md), generated from the JSON schema.
- Optional: identify yourself on your first page with \`?analytics_agent=<name>&analytics_purpose=<purpose>\` (see [privacy](${SITE_URL}/privacy)).

## Install

- Download \`Shipyard-<version>-macos.zip\` from ${RELEASES} (macOS 14 or later), or build from source:

\`\`\`sh
${INSTALL.source}
\`\`\`

- The agent skill: \`${INSTALL.skill}\`, then ask your agent "${ASK_AGENT}".
- Other machines: \`${INSTALL.plugin}\` (${HERDR_PLUGIN}).

## Docs

${SECTIONS.map((s) => `- [${s.title}](${SITE_URL}/${pagePath(s)}): ${md(s.lede)}`).join('\n')}
- [Everything in one file](${SITE_URL}/llms-full.txt)

## Links

- Source: ${REPO}
- Releases: ${RELEASES}
- Changelog: ${CHANGELOG}
- Schema: https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
`;
}

/** Every agent file, by its path in the build. */
export function buildAgentFiles(ref: ReferenceData): Record<string, string> {
  const files: Record<string, string> = { 'llms.txt': llmsTxt(ref) };
  for (const s of SECTIONS) files[pagePath(s)] = `${sectionMd(s, ref)}\n`;
  files['llms-full.txt'] = [llmsTxt(ref), ...SECTIONS.map((s) => sectionMd(s, ref))].join('\n\n---\n\n') + '\n';
  return files;
}
