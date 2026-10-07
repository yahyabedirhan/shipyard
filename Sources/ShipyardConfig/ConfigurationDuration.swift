import Foundation

/// How long a closed or finished item stays listed, as the file writes it:
/// a whole number and one unit, `s`, `m`, `h` or `d` (`"45s"`, `"30m"`,
/// `"12h"`, `"7d"`), or a bare `"0"`. No fractions, signs, spaces or
/// combined units. The configuration holds the window in seconds.
enum ConfigurationDuration {
    /// The units a window takes, largest first, and their seconds.
    static let units: [(unit: Character, seconds: Int)] = [("d", 86_400), ("h", 3600), ("m", 60), ("s", 1)]

    /// Why a window doesn't read.
    enum Rejection: Error, Equatable {
        case negative
        /// Not a whole number and one unit; `suggestion` is the spelling it
        /// most likely meant, when there is one.
        case malformed(suggestion: String?)
    }

    /// The window `text` writes, in seconds.
    static func parse(_ text: String) throws(Rejection) -> TimeInterval {
        if text == "0" { return 0 }
        if text.hasPrefix("-") { throw .negative }
        guard let last = text.last, let unit = units.first(where: { $0.unit == last }) else {
            throw .malformed(suggestion: suggestion(for: text))
        }
        let digits = text.dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }),
              let number = Int(digits)
        else { throw .malformed(suggestion: suggestion(for: text)) }
        let (seconds, overflow) = number.multipliedReportingOverflow(by: unit.seconds)
        guard !overflow else { throw .malformed(suggestion: nil) }
        return TimeInterval(seconds)
    }

    /// `seconds` in its largest whole unit: `604800` is `"7d"`, `5400` is
    /// `"90m"`, and `0` is `"0"`.
    static func text(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        guard whole > 0 else { return "0" }
        let unit = units.first { whole % $0.seconds == 0 } ?? units[units.count - 1]
        return "\(whole / unit.seconds)\(unit.unit)"
    }

    /// The words a unit is misspelt as, lowercased.
    private static let spellings: [String: Int] = {
        var words: [String: Int] = [:]
        for (seconds, names) in [
            (1, ["s", "sec", "secs", "second", "seconds"]),
            (60, ["m", "min", "mins", "minute", "minutes"]),
            (3600, ["h", "hr", "hrs", "hour", "hours"]),
            (86_400, ["d", "day", "days"]),
            (604_800, ["w", "wk", "wks", "week", "weeks"]),
        ] {
            for name in names { words[name] = seconds }
        }
        return words
    }()

    /// What a near miss meant: numbers (fractions too) each followed by a
    /// unit word, in any case and spacing (`"30min"`, `"2 hours"`,
    /// `"1h30m"`, `"1.5h"`), added up and written in the largest whole
    /// unit. `nil` when it doesn't read that way, or doesn't come to whole
    /// seconds.
    private static func suggestion(for text: String) -> String? {
        let compact = text.lowercased().filter { !$0.isWhitespace }
        var rest = Substring(compact)
        var total: Double = 0
        var parts = 0
        while !rest.isEmpty {
            let number = rest.prefix { ("0"..."9").contains($0) || $0 == "." }
            rest = rest.dropFirst(number.count)
            let word = rest.prefix { ("a"..."z").contains($0) }
            rest = rest.dropFirst(word.count)
            guard let value = Double(number), let seconds = spellings[String(word)] else { return nil }
            total += value * Double(seconds)
            parts += 1
        }
        guard parts > 0, total >= 0, total == total.rounded(), total < Double(Int.max) else { return nil }
        let suggested = self.text(total)
        return suggested == text ? nil : suggested
    }
}
