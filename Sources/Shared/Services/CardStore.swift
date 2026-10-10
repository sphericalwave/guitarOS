import Foundation
import SwiftData
import ScrollKit
import DiagnosticsKit

/// Finds or creates `SkillCard`s and grades them. Cards are made the first time a key is practised, never
/// seeded in bulk, so two fresh devices don't race to create 78 duplicates each; `dedupe()` on launch merges
/// what still collides.
@MainActor
final class CardStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all(kind: DrillKind) -> [SkillCard] {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<SkillCard>(predicate: #Predicate { $0.kind == raw })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Keys due now, most overdue first.
    func dueKeys(kind: DrillKind, now: Date = .now) -> [String] {
        all(kind: kind).filter { $0.srDueDate <= now }.sorted { $0.srDueDate < $1.srDueDate }.map(\.key)
    }

    func seenKeys(kind: DrillKind) -> Set<String> {
        Set(all(kind: kind).map(\.key))
    }

    /// The card for a key, created on first use.
    func card(kind: DrillKind, key: String) -> SkillCard {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<SkillCard>(predicate: #Predicate { $0.kind == raw && $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let card = SkillCard(kind: raw, key: key)
        context.insert(card)
        return card
    }

    /// Records an auto-graded attempt and reschedules the card.
    func record(kind: DrillKind, key: String, correct: Bool, response: TimeInterval, thresholds: AutoGrade.Thresholds, now: Date = .now) {
        let card = card(kind: kind, key: key)
        card.attempts += 1
        if correct {
            card.correct += 1
            card.meanResponse = AutoGrade.updatedMean(card.meanResponse, with: response, count: card.correct)
        }
        card.lastPracticed = now
        SM2.update(card: card, quality: AutoGrade.quality(correct: correct, response: response, thresholds: thresholds), now: now)
        save()
    }

    /// Merges cards that share a kind and key (CloudKit duplicates). Returns how many were removed.
    @discardableResult
    func dedupe() -> Int {
        let cards = (try? context.fetch(FetchDescriptor<SkillCard>())) ?? []
        var groups: [String: [SkillCard]] = [:]
        for card in cards { groups["\(card.kind)|\(card.key)", default: []].append(card) }
        var removed = 0
        for (_, group) in groups where group.count > 1 {
            let keep = group.min { $0.createdAt < $1.createdAt }!
            let merged = CardMerge.merge(group.map(\.snapshot))
            keep.apply(merged)
            for extra in group where extra !== keep {
                context.delete(extra)
                removed += 1
            }
        }
        if removed > 0 {
            save()
            ErrorLog.shared.info("Cards", "Merged \(removed) duplicate card(s)")
        }
        return removed
    }

    private func save() {
        do { try context.save() } catch { ErrorLog.shared.error("Cards", "Couldn't save cards", error: error) }
    }
}

extension SkillCard {
    var snapshot: CardMerge.Snapshot {
        CardMerge.Snapshot(attempts: attempts, correct: correct, meanResponse: meanResponse, best: best, lastPracticed: lastPracticed,
                           srInterval: srInterval, srEasinessFactor: srEasinessFactor, srRepetitions: srRepetitions, srDueDate: srDueDate)
    }

    func apply(_ snapshot: CardMerge.Snapshot) {
        attempts = snapshot.attempts
        correct = snapshot.correct
        meanResponse = snapshot.meanResponse
        best = snapshot.best
        lastPracticed = snapshot.lastPracticed
        srInterval = snapshot.srInterval
        srEasinessFactor = snapshot.srEasinessFactor
        srRepetitions = snapshot.srRepetitions
        srDueDate = snapshot.srDueDate
    }
}
