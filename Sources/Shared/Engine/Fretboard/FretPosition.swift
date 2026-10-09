import Foundation

/// One place on the neck: a string (1 = high E) and a fret (0 = open).
nonisolated struct FretPosition: Hashable, Sendable, Codable, Comparable {
    var string: Int
    var fret: Int

    /// Stable id for cards and settings: "s3f7".
    var key: String { "s\(string)f\(fret)" }

    init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
    }

    init?(key: String) {
        guard key.first == "s", let f = key.firstIndex(of: "f"),
              let string = Int(key[key.index(after: key.startIndex)..<f]),
              let fret = Int(key[key.index(after: f)...]) else { return nil }
        self.init(string: string, fret: fret)
    }

    /// Low string first, then up the neck — the order you'd read a scale shape.
    static func < (lhs: FretPosition, rhs: FretPosition) -> Bool {
        lhs.string != rhs.string ? lhs.string > rhs.string : lhs.fret < rhs.fret
    }
}
