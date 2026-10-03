import Foundation
import ShipyardControl
import Testing

/// The lease's rules, the owner test: sequences of leased requests at
/// given times (seconds from a fake clock's start), and what each got.
@Suite("The lease")
struct ControlLeaseTests {
    static let a = Holder(key: "CLAUDE_CODE_SESSION_ID=a", name: "Claude Code", place: "/work/shop")
    static let b = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")

    static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    /// What a request got, as one line: `a until 60 (started a)`, or
    /// `refused: a until 60 (ended a expired)`.
    static func read(_ decision: ControlLease.Decision) -> String {
        let answer = switch decision.answer {
        case .success(let term): "\(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        case .failure(.inUse(let term)): "refused: \(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        }
        let transitions = decision.transitions.map { transition in
            switch transition {
            case .started(let holder): "started \(name(holder))"
            case .renewed(let holder): "renewed \(name(holder))"
            case .ended(let holder, let ending): "ended \(name(holder)) \(ending)"
            }
        }
        return transitions.isEmpty ? answer : "\(answer) (\(transitions.joined(separator: ", ")))"
    }

    static func name(_ holder: Holder) -> String { holder == a ? "a" : holder == b ? "b" : holder.key }

    @Test("each request in turn takes, renews or is refused the lease", arguments: [
        // Implicit take: the first leased request takes it for a minute.
        ([(0.0, a)], ["a until 60 (started a)"]),
        // Each request renews it to a minute from then; an earlier one never shortens it.
        ([(0, a), (30, a), (35, a)], ["a until 60 (started a)", "a until 90 (renewed a)", "a until 95 (renewed a)"]),
        // Renewal stops at the cap, five minutes after it was taken.
        ([(0, a), (55, a), (110, a), (165, a), (220, a), (275, a)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)"]),
        // At the cap it ends; the holder's next request takes a new one.
        ([(0, a), (55, a), (110, a), (165, a), (220, a), (275, a), (300, a)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)", "a until 360 (ended a capped, started a)"]),
        // Another holder is refused while it's held, and the refusal renews nothing.
        ([(0, a), (30, b), (59, b)], ["a until 60 (started a)", "refused: a until 60", "refused: a until 60"]),
        // A minute after the holder's last request it's free: anyone takes it.
        ([(0, a), (30, b), (60, b)], ["a until 60 (started a)", "refused: a until 60", "b until 120 (ended a expired, started b)"]),
        // Once ended, its holder takes it again like anyone.
        ([(0, a), (90, a)], ["a until 60 (started a)", "a until 150 (ended a expired, started a)"]),
    ] as [([(TimeInterval, Holder)], [String])])
    func requests(steps: [(TimeInterval, Holder)], expected: [String]) {
        var lease = ControlLease()

        let seen = steps.map { seconds, holder in Self.read(lease.use(by: holder, at: Self.at(seconds))) }

        #expect(seen == expected)
    }

    @Test("a holder is the same across requests by key, and its latest name and place are kept")
    func sameKey() {
        var lease = ControlLease()
        let moved = Holder(key: Self.a.key, name: "Claude Code", place: "Herdr pane w3-1")

        _ = lease.use(by: Self.a, at: Self.at(0))
        let renewed = lease.use(by: moved, at: Self.at(10))

        #expect(renewed.answer == .success(ControlLease.Term(holder: moved, taken: Self.at(0), ends: Self.at(70))))
    }

    @Test("the lease is held until its end, then free; settling ends it once, saying why")
    func expiry() {
        var lease = ControlLease()
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.current(at: Self.at(59.9))?.holder == Self.a)
        #expect(lease.settle(at: Self.at(59.9)).isEmpty)
        #expect(lease.current(at: Self.at(60)) == nil)
        #expect(lease.settle(at: Self.at(60)) == [.ended(Self.a, .expired)])
        #expect(lease.settle(at: Self.at(61)).isEmpty)
    }

    @Test("the refusal names the holder, their place, when the lease ends and the seconds left")
    func refusal() throws {
        var lease = ControlLease()
        _ = lease.use(by: Self.b, at: Self.at(0))

        let refused = lease.use(by: Self.a, at: Self.at(12.5))

        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(12.5), timeZone: try #require(TimeZone(identifier: "UTC")))
            == "shipyard is in use by codex in Herdr pane w1-2 until 00:01:00 (48s left); `shipyard control take --wait <seconds>` to queue")
    }

    @Test("app status reports the held lease's holder, place, whole seconds left and waiters, and nothing once it's free")
    func status() {
        var lease = ControlLease()
        #expect(lease.status(at: Self.at(0)) == nil)
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.status(at: Self.at(12.5)) == AppStatus.Lease(holder: "Claude Code", place: "/work/shop", secondsLeft: 48, waiting: 0))
        #expect(lease.status(at: Self.at(60)) == nil)
    }
}
