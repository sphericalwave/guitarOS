import Foundation

/// Two devices starting fresh can each create a card for the same key before CloudKit syncs them.
/// Merging keeps the most progress: max repetitions, summed attempts, earliest due date.
nonisolated enum CardMerge {
    struct Snapshot: Equatable, Sendable {
        var attempts = 0
        var correct = 0
        var meanResponse = 0.0
        var best: Double?
        var lastPracticed: Date?
        var srInterval = 1
        var srEasinessFactor = 2.5
        var srRepetitions = 0
        var srDueDate = Date.now
    }

    static func merge(_ cards: [Snapshot]) -> Snapshot {
        guard var result = cards.first else { return Snapshot() }
        for card in cards.dropFirst() {
            let total = result.attempts + card.attempts
            result.meanResponse = total == 0 ? 0
                : (result.meanResponse * Double(result.attempts) + card.meanResponse * Double(card.attempts)) / Double(total)
            result.attempts = total
            result.correct += card.correct
            result.best = [result.best, card.best].compactMap { $0 }.max()
            result.lastPracticed = [result.lastPracticed, card.lastPracticed].compactMap { $0 }.max()
            if card.srRepetitions > result.srRepetitions || (card.srRepetitions == result.srRepetitions && card.srInterval > result.srInterval) {
                result.srRepetitions = card.srRepetitions
                result.srInterval = card.srInterval
                result.srEasinessFactor = card.srEasinessFactor
            }
            result.srDueDate = min(result.srDueDate, card.srDueDate)
        }
        return result
    }
}
