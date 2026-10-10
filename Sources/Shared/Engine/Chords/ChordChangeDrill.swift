import Foundation

/// One-minute changes between two chords, counted by the player for now (auto-detection is M6).
nonisolated enum ChordChangeDrill {
    static let duration: TimeInterval = 60

    struct Result: Equatable, Sendable {
        var changes: Int
        var seconds: TimeInterval
        var changesPerMinute: Double { seconds > 0 ? Double(changes) * 60 / seconds : 0 }
    }

    /// Among practised pairs, the one with the lowest best; nil when none has been practised.
    static func weakestPair(bests: [String: Double]) -> (String, String)? {
        guard let (key, _) = bests.min(by: { $0.value < $1.value }) else { return nil }
        return pair(fromKey: key)
    }

    static func pair(fromKey key: String) -> (String, String)? {
        guard key.hasPrefix("change:") else { return nil }
        let names = key.dropFirst("change:".count).split(separator: ">").map(String.init)
        guard names.count == 2 else { return nil }
        return (names[0], names[1])
    }

    /// SM-2 quality from a result against the pair's best: beating it is easy, within 80 % is good,
    /// below is hard. Counting means there's no "wrong", only slow.
    static func quality(changesPerMinute: Double, best: Double?) -> Int {
        guard let best, best > 0 else { return 4 }
        if changesPerMinute >= best { return 5 }
        if changesPerMinute >= best * 0.8 { return 4 }
        return 3
    }
}
