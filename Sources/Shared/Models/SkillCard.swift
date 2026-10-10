import Foundation
import SwiftData
import ScrollKit

/// One thing to get fluent at: a fret position, a chord shape, a chord change, a scale shape, an interval.
/// SM-2 schedules it; the mic (or a tap) grades it. CloudKit-safe: everything optional or defaulted,
/// no unique attributes, no relationships. Cards are created lazily on first practice and deduped on launch.
@Model
final class SkillCard {
    /// `DrillKind` raw value: fretPosition, chordShape, chordChange, scaleShape, interval, theory.
    var kind: String = ""
    /// Stable id within the kind: "fret:std:s3f7", "change:C-open>G-open".
    var key: String = ""
    var attempts: Int = 0
    var correct: Int = 0
    /// Seconds, rolling mean of correct answers' response times.
    var meanResponse: Double = 0
    /// Best score for kinds that have one (changes/min, BPM).
    var best: Double?
    var lastPracticed: Date?
    var createdAt: Date = Date.now

    var srInterval: Int = 1
    var srEasinessFactor: Double = 2.5
    var srRepetitions: Int = 0
    var srDueDate: Date = Date.now

    init(kind: String, key: String) {
        self.kind = kind
        self.key = key
        createdAt = .now
        srDueDate = .now
    }

    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

extension SkillCard: SpacedRepetitionCard {}

/// What kind of skill a card tracks.
nonisolated enum DrillKind: String, CaseIterable, Sendable {
    case fretPosition, chordShape, chordChange, scaleShape, interval, theory
}
