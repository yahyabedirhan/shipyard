/**
 * Who an analytics event comes from: a person (`human`) or an AI agent (`agent`).
 *
 * An agent says what it is with `?analytics_agent=<name>&analytics_purpose=<purpose>` on the first load.
 * Both take values only from the fixed lists below, so no agent can send text of its own.
 * A browser driven over WebDriver (`navigator.webdriver`) counts as an agent too.
 * The identity lasts for this tab only (session storage), so a person's later visits in the same browser stay human.
 *
 * Copied: yahyabedirhan/topographic keeps the same module in apps/playground/src, and yahyabedirhan/personal-website
 * keeps the same behaviour in src/privacy.js, src/analytics.js and src/errors.js. Change all three together;
 * docs/low-level-design.md > 'Copied modules' lists them.
 */

import { randomUuid } from './visitor';

export const AGENT_KEY = 'shipyard:agent';

/** Mainstream agents and harnesses. `chatgpt` covers ChatGPT and Codex. */
export const AGENT_NAMES = [
  'claude', 'chatgpt', 'gemini', 'jules', 'copilot', 'cursor', 'windsurf', 'opencode', 'pi', 'amp', 'droid',
  'cline', 'roo', 'kilo', 'aider', 'goose', 'kiro', 'devin', 'manus', 'grok', 'perplexity', 'other',
] as const;
export type AgentName = (typeof AGENT_NAMES)[number];

export const PURPOSES = ['testing', 'demo', 'creating', 'exploring', 'integrating', 'research', 'reverse-engineering', 'other'] as const;
export type Purpose = (typeof PURPOSES)[number];

export const isAgentName = (v: unknown): v is AgentName => typeof v === 'string' && (AGENT_NAMES as readonly string[]).includes(v);
export const isPurpose = (v: unknown): v is Purpose => typeof v === 'string' && (PURPOSES as readonly string[]).includes(v);

export interface AgentIdentity { name: AgentName; purpose: Purpose }
interface SavedAgent { id: string; name?: AgentName; purpose?: Purpose }

export interface ActorProps {
  actor: 'human' | 'agent';
  visitor_id?: string;
  agent_id?: string;
  agent_name?: AgentName;
  purpose?: Purpose;
  automation?: 'headless' | 'visible';
}

type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

/** This tab's session storage, or null where it is blocked. */
export function safeSession(): Store | null {
  try { return window.sessionStorage; } catch { return null; }
}

/** Reads `?analytics_agent` and `?analytics_purpose`. Both must be valid, or the identity is ignored. `handled` lists the keys to remove from the URL. */
export function readAgentParams(search: string): { identity: AgentIdentity | null; handled: string[] } {
  const q = new URLSearchParams(search);
  const handled = ['analytics_agent', 'analytics_purpose'].filter((k) => q.has(k));
  const name = q.get('analytics_agent');
  const purpose = q.get('analytics_purpose');
  return { identity: isAgentName(name) && isPurpose(purpose) ? { name, purpose } : null, handled };
}

export function loadAgent(store: Store | null): SavedAgent | null {
  try {
    const raw = store?.getItem(AGENT_KEY);
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<SavedAgent>;
    if (typeof v.id !== 'string' || !v.id) return null;
    return { id: v.id, name: isAgentName(v.name) ? v.name : undefined, purpose: isPurpose(v.purpose) ? v.purpose : undefined };
  } catch { return null; }
}

/** Saves the identity, keeping the tab's agent id when it already has one. With storage blocked, it lasts for this page. */
export function saveAgent(store: Store | null, identity: AgentIdentity | null): SavedAgent {
  const saved: SavedAgent = { id: loadAgent(store)?.id ?? randomUuid(), ...(identity ?? {}) };
  try { store?.setItem(AGENT_KEY, JSON.stringify(saved)); } catch { /* ignore */ }
  return saved;
}

export function forgetAgent(store: Store | null): void {
  try { store?.removeItem(AGENT_KEY); } catch { /* ignore */ }
}

export interface ActorSignals {
  /** `navigator.webdriver`. */
  webdriver: boolean;
  userAgent: string;
  /** The tab's saved agent, from `?analytics_agent`. */
  agent: SavedAgent | null;
}

/**
 * The actor properties for this tab's events. An identified agent or a WebDriver browser is an agent;
 * anything else is a person. `ids` makes the id that the actor needs, so a person never gets an agent id.
 */
export function resolveActor(s: ActorSignals, ids: { visitor: () => string; agent: () => string }): ActorProps {
  const automation = s.webdriver ? (/headless/i.test(s.userAgent) ? 'headless' : 'visible') : undefined;
  if (!s.agent && !automation) return { actor: 'human', visitor_id: ids.visitor() };
  return {
    actor: 'agent',
    agent_id: s.agent?.id ?? ids.agent(),
    ...(s.agent?.name ? { agent_name: s.agent.name } : {}),
    ...(s.agent?.purpose ? { purpose: s.agent.purpose } : {}),
    ...(automation ? { automation } : {}),
  };
}

/** The bucket a tool call's duration falls in, so no exact timing is sent. */
export function durationBucket(ms: number): 'under-1s' | '1-5s' | '5-30s' | 'over-30s' {
  return ms < 1000 ? 'under-1s' : ms < 5000 ? '1-5s' : ms < 30000 ? '5-30s' : 'over-30s';
}
