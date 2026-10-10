import Foundation
import SwiftData

/// One sitting. Blocks are saved as they finish, so a phone call mid-session loses nothing and Today
/// can offer to resume. CloudKit-safe: defaults everywhere, optional relationship with an inverse.
@Model
final class PracticeSession {
    var startedAt: Date = Date.now
    /// Set when the sitting is finished (or abandoned from the end screen); nil means resumable.
    var endedAt: Date?
    /// Seconds actually practised, summed from blocks.
    var duration: TimeInterval = 0
    /// Snapshot of the daily goal, so old days chart against the goal they had.
    var goalMinutes: Int = 20
    @Relationship(deleteRule: .cascade, inverse: \PracticeBlock.session)
    var blocks: [PracticeBlock]? = []

    init(startedAt: Date = .now, goalMinutes: Int) {
        self.startedAt = startedAt
        self.goalMinutes = goalMinutes
    }

    var isComplete: Bool { endedAt != nil }
}

/// One drill within a sitting.
@Model
final class PracticeBlock {
    /// `RoutineKind` raw value: tuner, fretboard, chordChange, scale, rhythm, ear, song, free.
    var kind: String = ""
    /// "Fretboard · Play it", "C → G".
    var title: String = ""
    var startedAt: Date = Date.now
    var duration: TimeInterval = 0
    var attempts: Int = 0
    var correct: Int = 0
    /// When a click was running.
    var bpm: Int?
    /// Kind-specific: changes/min, timing σ ms, accuracy.
    var score: Double?
    var session: PracticeSession?

    init(kind: String, title: String, startedAt: Date = .now) {
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
    }
}
