import Foundation

/// `shipyard herdr-event`: what the herdr-shipyard plugin's event hooks run,
/// so an agent Herdr marks blocked pings the user without remembering to.
/// It reads the event from `HERDR_PLUGIN_EVENT` and its payload from
/// `HERDR_PLUGIN_EVENT_JSON` (`{"event": …, "data": {"pane_id", "workspace_id",
/// "agent_status", "agent", …}}`):
///
/// - `pane.agent_status_changed` to `blocked` sends the ping
///   `herdr-<pane id>`, or replaces it when it's there (one per pane), the
///   way `shipyard ping --id` does: its sender the agent, its action the
///   pane, its title saying the agent is waiting in the pane's tab.
/// - `working`, `idle`, `done` and `unknown`, and `pane.closed`, withdraw
///   that ping, doing nothing when there's none.
/// - `tab.closed` and `workspace.closed`, which Herdr sends without a
///   `pane.closed` for the panes that went with them, withdraw every
///   `herdr-<pane>` ping whose pane `herdr pane list` no longer lists. When
///   Herdr can't list its panes, nothing is withdrawn.
///
/// The tab's label and the pane's working folder (whose `origin` files the
/// ping, as a ping's working folder does) come from `herdr pane get` and
/// `herdr tab get`, run through the environment's `run`; when Herdr can't
/// say, the title names the pane and the ping names no repository. A ping no
/// project takes is still saved, under none: a refusal would reach no one.
public enum HerdrEvent {
    /// The variable naming the event, as the hook's `on` names it.
    static let eventVariable = "HERDR_PLUGIN_EVENT"
    /// The variable holding the event's payload, as JSON.
    static let payloadVariable = "HERDR_PLUGIN_EVENT_JSON"
    /// The `herdr` the hook's Herdr runs as, which Herdr sets for its plugins.
    static let herdrVariable = "HERDR_BIN_PATH"

    static let statusChanged = "pane.agent_status_changed"
    static let paneClosed = "pane.closed"
    static let tabClosed = "tab.closed"
    static let workspaceClosed = "workspace.closed"

    /// The statuses that mean the agent went on, or isn't known to wait.
    static let resolvedStatuses: Set<String> = ["working", "idle", "done", "unknown"]

    /// Handles the event the environment names. `configuration` is read only
    /// to file a blocked agent's ping (a withdraw needs no projects); it
    /// fails the command when config.toml doesn't read.
    public static func run(
        environment: CommandEnvironment,
        configuration: () -> Result<Configuration, CommandResult>,
        resolved: @autoclosure () -> [String: [String]],
        store: PingStore,
        now: Date
    ) -> CommandResult {
        guard let event = environment.variables[eventVariable], !event.isEmpty else {
            return .usage("shipyard herdr-event: \(eventVariable) isn't set; Herdr's plugin event hooks run this command")
        }
        if event == tabClosed || event == workspaceClosed {
            return withdrawGone(event: event, environment: environment, store: store)
        }
        guard event == statusChanged || event == paneClosed else { return CommandResult() }
        let payload: Payload
        switch Payload.read(environment.variables[payloadVariable]) {
        case .success(let read): payload = read
        case .failure(let reason): return .failed("shipyard herdr-event: \(event): \(reason.message)")
        }
        let id = pingID(pane: payload.pane)
        if event == paneClosed { return withdraw(id, store: store) }
        guard let status = payload.status else {
            return .failed("shipyard herdr-event: \(event): \(payloadVariable) doesn't say the agent's status")
        }
        if resolvedStatuses.contains(status) { return withdraw(id, store: store) }
        guard status == "blocked" else { return CommandResult() }

        let read: Configuration
        switch configuration() {
        case .success(let configuration): read = configuration
        case .failure(let failure): return failure
        }
        let pane = PaneLookup(environment: environment).pane(payload.pane)
        // Herdr runs each event's hook on its own, so the agent may have gone
        // on (and that hook found nothing to withdraw) while this one looked
        // the pane up: Herdr's answer now wins over the event.
        if let current = pane.status, current != "blocked" {
            return resolvedStatuses.contains(current) ? withdraw(id, store: store) : CommandResult()
        }
        let request = PingCommand.Request(
            title: title(agent: payload.agent, place: pane.tabLabel ?? payload.pane),
            sender: payload.agent,
            action: .herdr(payload.pane),
            id: id
        )
        return PingCommand.send(
            request,
            folder: pane.folder,
            git: environment.git,
            platform: environment.platform,
            configuration: read,
            resolved: resolved(),
            store: store,
            now: now,
            unfiled: true
        )
    }

    /// The ping a pane's blocked agent sends: `herdr-` and the pane's id
    /// lowercased, each character still outside the id alphabet (lowercase
    /// letters, digits, `-` and `_`) made `-`, cut to an id's 64 characters:
    /// `wA:p3` is `herdr-wa-p3`. Lowercasing keeps panes apart because
    /// Herdr writes its id numbers in digits and uppercase letters only, so
    /// two of its ids never differ by case alone.
    static func pingID(pane: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let safe = String(pane.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return String(("herdr-" + safe).prefix(64))
    }

    /// "<Agent> is waiting in <place>", or "An agent is…" when Herdr didn't
    /// name it.
    static func title(agent: String?, place: String) -> String {
        guard let agent else { return "An agent is waiting in \(place)" }
        return agent.prefix(1).uppercased() + agent.dropFirst() + " is waiting in \(place)"
    }

    /// Takes back ping `id`, printing it; nothing when it's not there.
    private static func withdraw(_ id: String, store: PingStore) -> CommandResult {
        guard store.ping(id: id) != nil else { return CommandResult() }
        do {
            try store.remove(id: id)
        } catch {
            return .failed("shipyard herdr-event: couldn't remove the ping \(id) from \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: id + "\n")
    }

    /// Takes back each ping this command sent (`herdr-<pane>`, its action
    /// that pane) whose pane Herdr no longer lists, printing their ids. The
    /// payload isn't read: it names the tab or workspace, not its panes.
    private static func withdrawGone(event: String, environment: CommandEnvironment, store: PingStore) -> CommandResult {
        let sent = store.all().compactMap { ping -> (id: String, pane: String)? in
            guard case .herdr(let pane) = ping.action, ping.id == pingID(pane: pane) else { return nil }
            return (ping.id, pane)
        }
        guard !sent.isEmpty else { return CommandResult() }
        guard let open = PaneLookup(environment: environment).openPanes() else {
            return .failed("shipyard herdr-event: \(event): herdr pane list didn't answer, so no ping was withdrawn")
        }
        var output = ""
        for ping in sent where !open.contains(ping.pane) {
            let withdrawn = withdraw(ping.id, store: store)
            guard withdrawn.status == 0 else { return withdrawn }
            output += withdrawn.output
        }
        return CommandResult(output: output)
    }

    /// What an event's payload says.
    struct Payload: Equatable {
        var pane: String
        /// `agent_status`, lowercased; `nil` when it's not given.
        var status: String?
        /// The agent's name: `display_agent`, else `agent`; `nil` when neither is given.
        var agent: String?

        struct Unreadable: Error, Equatable {
            var message: String
        }

        /// Reads `json`, taking the fields from its `data` object (where
        /// Herdr puts them), or from the top level.
        static func read(_ json: String?) -> Result<Payload, Unreadable> {
            guard let json, !json.isEmpty else {
                return .failure(Unreadable(message: "\(payloadVariable) isn't set"))
            }
            guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
                return .failure(Unreadable(message: "\(payloadVariable) isn't a JSON object"))
            }
            let fields = object["data"] as? [String: Any] ?? object
            func text(_ key: String) -> String? {
                let value = (fields[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : nil
            }
            guard let pane = text("pane_id") else {
                return .failure(Unreadable(message: "\(payloadVariable) names no pane_id"))
            }
            return .success(Payload(pane: pane, status: text("agent_status")?.lowercased(), agent: text("display_agent") ?? text("agent")))
        }
    }

    /// What Herdr says about a pane, through `herdr pane get` and `herdr tab get`.
    struct PaneLookup {
        var environment: CommandEnvironment

        struct Pane: Equatable {
            /// Its tab's label; `nil` when Herdr didn't give one.
            var tabLabel: String?
            /// Its working folder; `nil` when Herdr didn't give one.
            var folder: URL?
            /// Its agent's status now, lowercased; `nil` when Herdr didn't give one.
            var status: String?
        }

        /// The `herdr` to run: the one Herdr says it runs as, else the one
        /// `HerdrFocus` finds.
        private var herdr: String? {
            if let own = environment.variables[herdrVariable], own.hasPrefix("/"), environment.isExecutable(own) { return own }
            let home = environment.variables["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
            return HerdrFocus.locate(home: home, pathEnvironment: environment.variables["PATH"], isExecutable: environment.isExecutable)
        }

        /// What Herdr says about `id`: as much as it answered, nothing when
        /// it can't be run or doesn't know the pane.
        func pane(_ id: String) -> Pane {
            guard let herdr, let pane = result(herdr, ["pane", "get", id])?["pane"] as? [String: Any] else { return Pane() }
            let folder = (pane["cwd"] as? String).flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            let status = (pane["agent_status"] as? String)?.lowercased()
            guard let tab = pane["tab_id"] as? String,
                  let label = (result(herdr, ["tab", "get", tab])?["tab"] as? [String: Any])?["label"] as? String,
                  !label.trimmingCharacters(in: .whitespaces).isEmpty
            else { return Pane(folder: folder, status: status) }
            return Pane(tabLabel: label, folder: folder, status: status)
        }

        /// The ids of every pane Herdr has open, from `herdr pane list`;
        /// `nil` when it can't be run or its answer doesn't read.
        func openPanes() -> Set<String>? {
            guard let herdr, let panes = result(herdr, ["pane", "list"])?["panes"] as? [[String: Any]] else { return nil }
            return Set(panes.compactMap { $0["pane_id"] as? String })
        }

        /// The `result` of running `herdr` with `arguments`, when it worked.
        private func result(_ herdr: String, _ arguments: [String]) -> [String: Any]? {
            guard let output = environment.run(herdr, arguments), output.status == 0,
                  let answer = (try? JSONSerialization.jsonObject(with: Data(output.standardOutput.utf8))) as? [String: Any]
            else { return nil }
            return answer["result"] as? [String: Any]
        }
    }
}
