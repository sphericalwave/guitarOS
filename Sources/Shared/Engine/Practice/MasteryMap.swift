import Foundation

/// How well each position is known, for the heatmap on the fretboard: 0 unseen, towards 1 mastered.
nonisolated enum MasteryMap {
    struct Entry: Equatable, Sendable {
        var accuracy: Double
        var repetitions: Int
        var isDue: Bool
    }

    /// Combines accuracy with how many spaced reviews it has survived: a position answered right once is not
    /// yet known; one right across several widening intervals is.
    static func mastery(_ entry: Entry) -> Double {
        let schedule = min(Double(entry.repetitions), 5) / 5
        return entry.accuracy * (0.4 + 0.6 * schedule)
    }

    static func entries(cards: [SkillCard], tuning: Tuning, now: Date = .now) -> [FretPosition: Entry] {
        var result: [FretPosition: Entry] = [:]
        let prefix = "fret:\(tuning.description):"
        for card in cards where card.kind == DrillKind.fretPosition.rawValue && card.key.hasPrefix(prefix) {
            guard let position = FretboardDrill.position(fromCardKey: card.key) else { continue }
            result[position] = Entry(accuracy: card.accuracy, repetitions: card.srRepetitions, isDue: card.srDueDate <= now)
        }
        return result
    }
}
