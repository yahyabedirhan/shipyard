/// The prefix a new notes database's `No.` gets, as the shipyard skill's
/// notes reference says to pick one: two to five uppercase letters from
/// the project's title (`shipyard` → `SHIP`), not already another
/// database's.
enum NotePrefix {
    /// The lengths tried, in order: four reads best, then shorter, longer,
    /// and the shortest.
    private static let lengths = [4, 3, 5, 2]

    /// The first free prefix for project `name`, given the `taken` ones
    /// (any case): the name's first letters (A to Z only) at each length;
    /// then its first letter followed by later letters of the name, in
    /// order; then its first letter and any letter; then any two letters.
    /// `nil` only when every two-letter prefix is taken too.
    static func choose(for name: String, taken: Set<String>) -> String? {
        let taken = Set(taken.map { $0.uppercased() })
        let letters = Array(name.uppercased().filter { $0.isASCII && $0.isLetter })
        let alphabet = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { Character(UnicodeScalar($0)) }
        func free(_ candidate: [Character]) -> Bool { !taken.contains(String(candidate)) }

        for length in lengths where letters.count >= length {
            let candidate = Array(letters.prefix(length))
            if free(candidate) { return String(candidate) }
        }
        if let first = letters.first {
            let rest = Array(letters.dropFirst())
            for length in lengths where rest.count >= length - 1 {
                if let found = firstSubsequence(of: rest, count: length - 1, where: { free([first] + $0) }) {
                    return String([first] + found)
                }
            }
            if let letter = alphabet.first(where: { free([first, $0]) }) { return String([first, letter]) }
        }
        for first in alphabet {
            if let second = alphabet.first(where: { free([first, $0]) }) { return String([first, second]) }
        }
        return nil
    }

    /// The first of `letters`' subsequences of `count` letters, in order,
    /// that `accept` takes.
    private static func firstSubsequence(
        of letters: [Character],
        count: Int,
        where accept: ([Character]) -> Bool
    ) -> [Character]? {
        func search(from start: Int, _ picked: [Character]) -> [Character]? {
            if picked.count == count { return accept(picked) ? picked : nil }
            guard start < letters.count, letters.count - start >= count - picked.count else { return nil }
            for index in start..<letters.count {
                if let found = search(from: index + 1, picked + [letters[index]]) { return found }
            }
            return nil
        }
        return search(from: 0, [])
    }
}
