import Foundation
import Observation
import SwiftData
import DiagnosticsKit

/// Runs today's routine block by block. The session is inserted when it starts and every finished block
/// is saved at once, so nothing is lost if the app is killed; Today offers to resume an unfinished one.
@Observable
@MainActor
final class SessionRunnerViewModel {
    struct Summary: Equatable {
        var minutes: Int
        var cardsRight: Int
        var cardsTotal: Int
        var streak: Int
        var dueTomorrow: Int
    }

    private(set) var routine: [RoutineItem]
    private(set) var index = 0
    private(set) var isFinished = false
    private(set) var summary: Summary?
    /// Seconds elapsed in the current block, for the header.
    private(set) var elapsed: TimeInterval = 0

    let session: PracticeSession
    let cards: CardStore
    private let context: ModelContext
    @ObservationIgnored private var blockStart = Date.now
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var current: RoutineItem? { index < routine.count && !isFinished ? routine[index] : nil }
    var minutesLeft: Int { routine.dropFirst(index).reduce(0) { $0 + $1.minutes } - Int(elapsed / 60) }
    var progress: Double { routine.isEmpty ? 1 : Double(index) / Double(routine.count) }
    /// Current block's planned length is up.
    var isBlockTimeUp: Bool { current.map { elapsed >= Double($0.minutes) * 60 } ?? false }

    /// Starts a fresh session (inserted and saved immediately) or resumes `existing`.
    init(routine: [RoutineItem], goalMinutes: Int, context: ModelContext, resuming existing: PracticeSession? = nil) {
        self.routine = routine
        self.context = context
        cards = CardStore(context: context)
        if let existing {
            session = existing
            // Skip the kinds already done today in this session.
            let done = Set((existing.blocks ?? []).map(\.kind))
            index = routine.firstIndex { !done.contains($0.kind.rawValue) } ?? routine.count
        } else {
            session = PracticeSession(goalMinutes: goalMinutes)
            context.insert(session)
            save()
        }
        beginBlock()
    }

    /// Finishes the current block, recording what it did, and moves on.
    func completeBlock(attempts: Int = 0, correct: Int = 0, score: Double? = nil, bpm: Int? = nil) {
        guard let item = current else { return }
        let block = PracticeBlock(kind: item.kind.rawValue, title: item.title, startedAt: blockStart)
        block.duration = Date.now.timeIntervalSince(blockStart)
        block.attempts = attempts
        block.correct = correct
        block.score = score
        block.bpm = bpm
        block.session = session
        context.insert(block)
        session.duration += block.duration
        save()
        index += 1
        if index >= routine.count { finish() } else { beginBlock() }
    }

    func skipBlock() {
        guard current != nil else { return }
        index += 1
        if index >= routine.count { finish() } else { beginBlock() }
    }

    /// Ends the sitting early; what was done stays logged.
    func endEarly() {
        finish()
    }

    func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Private

    private func beginBlock() {
        blockStart = .now
        elapsed = 0
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                elapsed = Date.now.timeIntervalSince(blockStart)
            }
        }
    }

    private func finish() {
        stopTicking()
        session.endedAt = .now
        save()
        isFinished = true
        let blocks = session.blocks ?? []
        let fret = blocks.filter { $0.kind == RoutineKind.fretboard.rawValue }
        let all = (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
        let tomorrow = PracticeStats.calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        summary = Summary(
            minutes: Int((session.duration / 60).rounded()),
            cardsRight: fret.reduce(0) { $0 + $1.correct },
            cardsTotal: fret.reduce(0) { $0 + $1.attempts },
            streak: PracticeStats.streak(sessions: all.map { ($0.startedAt, $0.duration) }),
            dueTomorrow: cards.dueKeys(kind: .fretPosition, now: tomorrow).count
        )
    }

    private func save() {
        do { try context.save() } catch { ErrorLog.shared.error("Log", "Couldn't save the session", error: error) }
    }
}
