import Foundation
import Observation
import SwiftData
import ScrollKit
import DiagnosticsKit

/// One-minute changes between two chords: a countdown, a tap counter, the result against the best.
/// With auto-count on (beta), the mic counts instead: each strum is verified against the chord the hand
/// should be reaching, and a clean one counts as a change. Taps still work as a correction.
@Observable
@MainActor
final class ChordChangeViewModel {
    enum Phase: Equatable { case ready, running, done(ChordChangeDrill.Result, isNewBest: Bool) }

    var first: ChordVoicing
    var second: ChordVoicing
    private(set) var phase: Phase = .ready
    private(set) var changes = 0
    private(set) var remaining: TimeInterval = ChordChangeDrill.duration
    /// Which chord should be held now, alternating with each change.
    var showingFirst: Bool { changes % 2 == 0 }
    /// Auto-count: what the last strum sounded like.
    private(set) var feedback: ChordChangeCounter.Feedback?
    /// Auto-count: strums heard this run.
    private(set) var strums = 0

    let cards: CardStore
    let context: ModelContext
    /// The mic, when auto-count is on; nil means self-counting.
    let audio: AudioHub?
    /// Set when the drill runs inside a session, so the block is logged there instead of standalone.
    var logsStandalone = true

    var isAuto: Bool { audio != nil }
    /// Strings (1 = high E) of the chord being reached that the last strum missed, for the grid.
    var highlightStrings: Set<Int> {
        guard let feedback, !feedback.counted, feedback.heard == nil else { return [] }
        return Set(feedback.verdict.missing)
    }

    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var counter: ChordChangeCounter?
    @ObservationIgnored private var listenerID: UUID?
    @ObservationIgnored private var manualChanges = 0

    init(first: ChordVoicing, second: ChordVoicing, context: ModelContext, audio: AudioHub? = nil) {
        self.first = first
        self.second = second
        self.context = context
        self.audio = audio
        cards = CardStore(context: context)
    }

    var key: String { ChordVoicing.changeKey(first, second) }
    var best: Double? { cards.all(kind: .chordChange).first { $0.key == key }?.best }
    var title: String { "\(first.name) → \(second.name)" }

    func start() {
        changes = 0
        manualChanges = 0
        strums = 0
        feedback = nil
        remaining = ChordChangeDrill.duration
        startedAt = .now
        phase = .running
        if let audio { listen(with: audio) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                remaining = max(0, ChordChangeDrill.duration - Date.now.timeIntervalSince(startedAt))
                if remaining == 0 { finish(); return }
            }
        }
    }

    /// A tap: the only count when self-counting, a correction when the mic is counting.
    func countChange() {
        guard phase == .running else { return }
        manualChanges += 1
        changes = (counter?.changes ?? 0) + manualChanges
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        if phase == .running { finish(early: true) }
    }

    func reset() { phase = .ready; changes = 0; feedback = nil; remaining = ChordChangeDrill.duration }

    /// Changes/min history for this pair, oldest first, from logged blocks.
    func history() -> [(date: Date, changesPerMinute: Double)] {
        let title = self.title
        let kind = RoutineKind.chordChange.rawValue
        let descriptor = FetchDescriptor<PracticeBlock>(predicate: #Predicate { $0.kind == kind && $0.title == title }, sortBy: [SortDescriptor(\.startedAt)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap { block in block.score.map { (block.startedAt, $0) } }
    }

    // MARK: Private

    private func listen(with audio: AudioHub) {
        let tuning = Tuning.named(description: UserDefaults.standard.string(forKey: SettingsKey.tuning) ?? "") ?? .standard
        let counter = ChordChangeCounter(first: first, second: second, tuning: tuning)
        self.counter = counter
        let listener = StrumListener(
            profile: audio.inputProfile.detectorProfile(referenceA: audio.referenceA),
            sensitivity: audio.sensitivity,
            candidates: Set(first.pitches(in: tuning) + second.pitches(in: tuning))
        ) { [weak self] strum in
            Task { @MainActor in self?.heard(strum) }
        }
        audio.acquire()
        listenerID = audio.addFrameListener { buffer, time in listener.handle(buffer, time) }
    }

    private func stopListening() {
        guard let audio, let listenerID else { return }
        audio.removeFrameListener(listenerID)
        audio.release()
        self.listenerID = nil
    }

    private func heard(_ strum: StrumAnalyzer.Strum) {
        guard phase == .running, counter != nil else { return }
        strums += 1
        feedback = counter!.strum(strum.present, at: strum.time)
        changes = counter!.changes + manualChanges
    }

    private func finish(early: Bool = false) {
        ticker?.cancel()
        ticker = nil
        stopListening()
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

    /// Auto-counted runs log every strum as an attempt and the clean changes as correct; self-counted
    /// runs have no wrong, only slow.
    func block(for result: ChordChangeDrill.Result, in session: PracticeSession?) -> PracticeBlock {
        let block = PracticeBlock(kind: RoutineKind.chordChange.rawValue, title: title, startedAt: startedAt)
        block.duration = result.seconds
        block.attempts = isAuto ? max(strums, result.changes) : result.changes
        block.correct = result.changes
        block.score = result.changesPerMinute
        block.session = session
        return block
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
