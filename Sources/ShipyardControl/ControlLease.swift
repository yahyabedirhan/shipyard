import Foundation

/// The lease's rules: who holds app control, and until when. One agent at
/// a time holds it. A leased request from the holder, or from anyone while
/// it's free, takes or renews it; one from another holder is refused. It
/// ends by itself `renewal` after the holder's last request, and `cap`
/// after it was taken at most, so a crashed agent can't keep it.
///
/// A pure value, given the time on each call: the app owns the one
/// instance and drives it, and its answers and transitions are all it
/// needs to refuse, redraw and notify.
public struct ControlLease: Equatable, Sendable {
    /// How long after the holder's last request the lease ends.
    public static let renewal: TimeInterval = 60
    /// How long after it was taken the lease ends, however it's renewed.
    public static let cap: TimeInterval = 5 * 60

    /// A lease held: by whom, when it was taken and when it ends.
    public struct Term: Equatable, Sendable {
        public var holder: Holder
        public var taken: Date
        public var ends: Date

        public init(holder: Holder, taken: Date, ends: Date) {
            self.holder = holder
            self.taken = taken
            self.ends = ends
        }

        /// The latest it can end, however it's renewed.
        public var capped: Date { taken.addingTimeInterval(ControlLease.cap) }

        /// Whole seconds left at `now`, rounded up: 0 once it has ended.
        public func secondsLeft(at now: Date) -> Int {
            max(0, Int(ends.timeIntervalSince(now).rounded(.up)))
        }
    }

    /// A change in who holds the lease, for the app to redraw and notify.
    public enum Transition: Equatable, Sendable {
        case started(Holder)
        case renewed(Holder)
        case ended(Holder, Ending)
    }

    /// Why a lease ended.
    public enum Ending: Equatable, Sendable {
        /// Its holder sent nothing for `renewal`.
        case expired
        /// It reached `cap`.
        case capped
    }

    /// Why a request isn't granted.
    public enum Refusal: Error, Equatable, Sendable {
        /// Another holder has the lease.
        case inUse(Term)

        /// The refusal as the agent reads it, its times in `timeZone`.
        public func message(at now: Date, timeZone: TimeZone) -> String {
            switch self {
            case .inUse(let term):
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = "HH:mm:ss"
                return "shipyard is in use by \(term.holder.name) in \(term.holder.place) until \(formatter.string(from: term.ends)) "
                    + "(\(term.secondsLeft(at: now))s left); `shipyard control take --wait <seconds>` to queue"
            }
        }
    }

    /// What a request got, and what changed on the way.
    public struct Decision: Equatable, Sendable {
        /// The lease the request holds now, or why it doesn't.
        public var answer: Result<Term, Refusal>
        /// In order: a lease that ran out ends before the next one starts.
        public var transitions: [Transition]
    }

    /// The lease as of the last call; it may have ended since, so it's
    /// read through `current(at:)`.
    private var term: Term?

    public init() {}

    /// The lease an app launched with `environment` starts with at `now`:
    /// the one a relaunch handed over in `handoverVariable`, keeping when
    /// it was taken and so its cap, and posting no transition; free when
    /// there's none, it doesn't read, or it has already ended.
    public init(environment: [String: String], at now: Date) {
        guard let json = environment[Self.handoverVariable],
              var term = try? JSONDecoder().decode(Term.self, from: Data(json.utf8)) else { return }
        term.ends = min(term.ends, term.capped)
        guard now < term.ends else { return }
        self.term = term
    }

    /// The launch environment's variable a relaunch hands the lease over in.
    public static let handoverVariable = "SHIPYARD_CONTROL_LEASE"

    /// What a relaunch adds to the launched app's environment to hand
    /// `term` over: `handoverVariable`, as one small JSON object,
    /// `{"ends":<seconds since 1970>,"holder":{…},"taken":<seconds since 1970>}`.
    public static func handover(_ term: Term) -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding strings and numbers can't fail.
        return [handoverVariable: String(decoding: try! encoder.encode(term), as: UTF8.self)]
    }

    /// The lease held at `now`, or nil when it's free.
    public func current(at now: Date) -> Term? {
        guard let term, now < term.ends else { return nil }
        return term
    }

    /// Ends a lease that has run out by `now`: its `ended` transition, or
    /// none when nothing ended.
    public mutating func settle(at now: Date) -> [Transition] {
        guard let term, now >= term.ends else { return [] }
        self.term = nil
        return [.ended(term.holder, term.ends >= term.capped ? .capped : .expired)]
    }

    /// A leased request from `holder` at `now`: granted when `holder` holds
    /// the lease (renewing it to `renewal` from now, never past the cap),
    /// or when it's free (taking it); refused while another holds it.
    public mutating func use(by holder: Holder, at now: Date) -> Decision {
        var transitions = settle(at: now)
        if var term {
            guard term.holder.key == holder.key else {
                return Decision(answer: .failure(.inUse(term)), transitions: transitions)
            }
            term.ends = min(max(term.ends, now.addingTimeInterval(Self.renewal)), term.capped)
            // The holder's name and place are as its latest request says.
            term.holder = holder
            self.term = term
            transitions.append(.renewed(holder))
            return Decision(answer: .success(term), transitions: transitions)
        }
        let term = Term(holder: holder, taken: now, ends: now.addingTimeInterval(Self.renewal))
        self.term = term
        transitions.append(.started(holder))
        return Decision(answer: .success(term), transitions: transitions)
    }

    /// The lease as `app status` reports it at `now`, or nil when it's free.
    public func status(at now: Date) -> AppStatus.Lease? {
        current(at: now).map {
            AppStatus.Lease(holder: $0.holder.name, place: $0.holder.place, secondsLeft: $0.secondsLeft(at: now), waiting: 0)
        }
    }
}

/// A term as it goes in the quit's reply and the relaunch's environment:
/// its times as seconds since 1970, whatever the coder's date strategy.
extension ControlLease.Term: Codable {
    private enum CodingKeys: String, CodingKey {
        case holder, taken, ends
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holder = try container.decode(Holder.self, forKey: .holder)
        taken = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .taken))
        ends = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .ends))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holder, forKey: .holder)
        try container.encode(taken.timeIntervalSince1970, forKey: .taken)
        try container.encode(ends.timeIntervalSince1970, forKey: .ends)
    }
}
