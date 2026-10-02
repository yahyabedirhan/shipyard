import Foundation

/// A coding agent shipyard recognises in a ping's sender (`--from`), so its
/// row and hover card can show the agent's mark.
///
/// Shipyard bundles no agent's logo: their makers' terms don't allow it
/// (`docs/references/agent-icons.md`). Each agent gets a neutral mark of
/// shipyard's own instead, a two-letter monogram in a circle of its hue,
/// which imitates no agent's logo or brand colour.
public enum KnownAgent: String, CaseIterable, Hashable, Sendable {
    case claude, codex, opencode, cursor, pi, gemini, copilot, amp, droid

    /// The one table: each agent's names as a sender may write them
    /// (lowercase, without spaces or dashes), and its mark. Monograms keep
    /// the agents that share an initial apart; hues are spread around the
    /// wheel, away from red, which says a check or a run failed.
    private var entry: (aliases: Set<String>, mark: AgentMark) {
        switch self {
        case .claude: (["claude", "claudecode"], AgentMark(monogram: "Cl", hue: 0.47))
        case .codex: (["codex", "codexcli", "openaicodex"], AgentMark(monogram: "Cx", hue: 0.62))
        case .opencode: (["opencode"], AgentMark(monogram: "Oc", hue: 0.33))
        case .cursor: (["cursor", "cursoragent", "cursorcli"], AgentMark(monogram: "Cu", hue: 0.55))
        case .pi: (["pi", "piagent", "picodingagent"], AgentMark(monogram: "Pi", hue: 0.08))
        case .gemini: (["gemini", "geminicli"], AgentMark(monogram: "Ge", hue: 0.15))
        case .copilot: (["copilot", "copilotcli", "githubcopilot"], AgentMark(monogram: "Co", hue: 0.9))
        case .amp: (["amp", "ampcode"], AgentMark(monogram: "Am", hue: 0.72))
        case .droid: (["droid", "factorydroid"], AgentMark(monogram: "Dr", hue: 0.82))
        }
    }

    /// The agent's mark.
    public var mark: AgentMark { entry.mark }

    /// The agent a sender names, or `nil`. Case, spaces, dashes and other
    /// punctuation don't count, and words after the agent's name are
    /// allowed: "Claude Code", "claude-code" and "claude: fix totals" are
    /// all Claude. The name has to come first and whole: "pipeline" and
    /// "my claude" name no agent.
    public init?(sender: String) {
        let words = sender.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        // The longest run of leading words that names an agent.
        for count in stride(from: words.count, through: 1, by: -1) {
            let name = words.prefix(count).joined()
            if let agent = Self.allCases.first(where: { $0.entry.aliases.contains(name) }) {
                self = agent
                return
            }
        }
        return nil
    }
}

/// How shipyard draws a known agent: its monogram on a circle of its hue.
public struct AgentMark: Hashable, Sendable {
    /// Two letters, the first capital: "Cl".
    public var monogram: String
    /// Where its colour sits on the colour wheel, from 0 up to 1; the app
    /// picks the saturation and brightness for light and dark.
    public var hue: Double

    public init(monogram: String, hue: Double) {
        self.monogram = monogram
        self.hue = hue
    }
}
