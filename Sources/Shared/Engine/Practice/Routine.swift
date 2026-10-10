import Foundation

/// What a block of practice is.
nonisolated enum RoutineKind: String, CaseIterable, Sendable, Codable {
    case tuner, fretboard, chordChange, scale, rhythm, ear, song, free

    var title: String {
        switch self {
        case .tuner: "Tune up"
        case .fretboard: "Fretboard notes"
        case .chordChange: "Chord changes"
        case .scale: "Scale"
        case .rhythm: "Rhythm"
        case .ear: "Ear"
        case .song: "Song"
        case .free: "Free practice"
        }
    }

    var icon: String {
        switch self {
        case .tuner: "tuningfork"
        case .fretboard: "guitars"
        case .chordChange: "music.note.list"
        case .scale: "waveform.path"
        case .rhythm: "metronome"
        case .ear: "ear"
        case .song: "music.quarternote.3"
        case .free: "timer"
        }
    }
}

/// One planned block: what to do and for how long.
nonisolated struct RoutineItem: Equatable, Sendable, Identifiable, Codable {
    var kind: RoutineKind
    var title: String
    var minutes: Int
    /// Kind-specific detail: the drill mode for fretboard, the chord pair for changes.
    var detail: String?

    var id: String { "\(kind.rawValue)|\(title)" }
}

/// Builds today's routine from what's due and the time available. Every block can be skipped or
/// swapped; this is the sensible default, not a contract.
nonisolated enum RoutineBuilder {
    struct Inputs: Equatable, Sendable {
        var goalMinutes: Int
        var dueFretCards: Int
        var learnedFretCards: Int
        /// Minutes already practised today, so a resumed day only plans the remainder.
        var minutesDoneToday: Int = 0
    }

    /// Seconds a fretboard card takes on average, for sizing the block.
    static let secondsPerCard = 12.0

    static func routine(_ inputs: Inputs) -> [RoutineItem] {
        let remaining = max(inputs.goalMinutes - inputs.minutesDoneToday, 5)
        var items: [RoutineItem] = [RoutineItem(kind: .tuner, title: "Tune up", minutes: 1)]
        var left = remaining - 1

        // Due cards first; a fresh neck gets a short introduction instead.
        let cards = inputs.dueFretCards > 0 ? inputs.dueFretCards : (inputs.learnedFretCards < 12 ? 12 : 0)
        if cards > 0 {
            let minutes = min(max(Int((Double(cards) * secondsPerCard / 60).rounded(.up)), 3), max(3, left / 2))
            items.append(RoutineItem(kind: .fretboard, title: inputs.dueFretCards > 0 ? "\(inputs.dueFretCards) due notes" : "Learn the neck",
                                     minutes: minutes, detail: FretboardDrill.Mode.findTheNote.rawValue))
            left -= minutes
        }
        if left > 0 {
            items.append(RoutineItem(kind: .free, title: "Free practice", minutes: left))
        }
        return items
    }

    static func totalMinutes(_ items: [RoutineItem]) -> Int { items.reduce(0) { $0 + $1.minutes } }
}
