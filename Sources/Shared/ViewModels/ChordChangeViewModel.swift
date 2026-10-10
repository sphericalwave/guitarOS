import Foundation
import Observation
import SwiftData
import ScrollKit
import DiagnosticsKit

/// One-minute changes between two chords: a countdown, a tap counter, the result against the best.
@Observable
@MainActor
final class ChordChangeViewModel {
    enum Phase: Equatable { case ready, running, done(ChordChangeDrill.Result, isNewBest: Bool) }

    var first: ChordVoicing
    var second: ChordVoicing
    private(set) var phase: Phase = .ready
    private(set) var changes = 0
    private(set) var remaining: TimeInterval = ChordChangeDrill.duration
    /// Which chord should be held now, alternating with each tap.
    var showingFirst: Bool { changes % 2 == 0 }

    let cards: CardStore
    let context: ModelContext
    /// Set when the drill runs inside a session, so the block is logged there instead of standalone.
    var logsStandalone = true

    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(first: ChordVoicing, second: ChordVoicing, context: ModelContext) {
        self.first = first
        self.second = second
        self.context = context
        cards = CardStore(context: context)
    }

    var key: String { ChordVoicing.changeKey(first, second) }
    var best: Double? { cards.all(kind: .chordChange).first { $0.key == key }?.best }
    var title: String { "\(first.name) → \(second.name)" }

    func start() {
        changes = 0
        remaining = ChordChangeDrill.duration
        startedAt = .now
        phase = .running
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                remaining = max(0, ChordChangeDrill.duration - Date.now.timeIntervalSince(startedAt))
                if remaining == 0 { finish(); return }
            }
        }
    }

    func countChange() {
        guard phase == .running else { return }
        changes += 1
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        if phase == .running { finish(early: true) }
    }

    func reset() { phase = .ready; changes = 0; remaining = ChordChangeDrill.duration }

    /// Changes/min history for this pair, oldest first, from logged blocks.
    func history() -> [(date: Date, changesPerMinute: Double)] {
        let title = self.title
        let kind = RoutineKind.chordChange.rawValue
        let descriptor = FetchDescriptor<PracticeBlock>(predicate: #Predicate { $0.kind == kind && $0.title == title }, sortBy: [SortDescriptor(\.startedAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap { block in block.score.map { (block.startedAt, $0) } }
    }

    // MARK: Private

    private func finish(early: Bool = false) {
        ticker?.cancel()
        ticker = nil
        let seconds = early ? Date.now.timeIntervalSince(startedAt) : ChordChangeDrill.duration
        let result = ChordChangeDrill.Result(changes: changes, seconds: seconds)
        let card = cards.card(kind: .chordChange, key: key)
        let previousBest = card.best
        let isNewBest = !early && (previousBest.map { result.changesPerMinute > $0 } ?? true) && changes > 0
        card.attempts += 1
        card.correct += 1
        card.lastPracticed = .now
        if isNewBest { card.best = result.changesPerMinute }
        SM2.update(card: card, quality: ChordChangeDrill.quality(changesPerMinute: result.changesPerMinute, best: previousBest))
        if logsStandalone { logStandalone(result) }
        do { try context.save() } catch { ErrorLog.shared.error("Chords", "Couldn't save the change", error: error) }
        phase = .done(result, isNewBest: isNewBest)
    }

    /// Outside a session, a drill still counts as practice: a one-block session of its own.
    private func logStandalone(_ result: ChordChangeDrill.Result) {
        let session = PracticeSession(startedAt: startedAt, goalMinutes: UserDefaults.standard.integer(forKey: SettingsKey.dailyGoalMinutes).nonZero ?? 20)
        session.duration = result.seconds
        session.endedAt = .now
        context.insert(session)
        context.insert(block(for: result, in: session))
    }

    func block(for result: ChordChangeDrill.Result, in session: PracticeSession?) -> PracticeBlock {
        let block = PracticeBlock(kind: RoutineKind.chordChange.rawValue, title: title, startedAt: startedAt)
        block.duration = result.seconds
        block.attempts = result.changes
        block.correct = result.changes
        block.score = result.changesPerMinute
        block.session = session
        return block
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
