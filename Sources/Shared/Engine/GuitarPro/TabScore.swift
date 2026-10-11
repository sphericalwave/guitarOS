import Foundation

/// A tab as Guitar Pro stores it: measures with time signatures and repeats, tracks with string tunings,
/// beats per voice, notes as string + fret. Ticks are 960 per quarter note.
nonisolated struct TabScore: Equatable, Sendable {
    var title = ""
    var artist = ""
    var album = ""
    /// Starting tempo, BPM.
    var tempo = 120
    var measureHeaders: [TabMeasureHeader] = []
    var tracks: [TabTrack] = []

    static let ticksPerQuarter = 960

    /// Tracks a player can follow: strings, not drums.
    var guitarTracks: [Int] { tracks.indices.filter { !tracks[$0].isPercussion && !tracks[$0].tunings.isEmpty } }
}

nonisolated struct TabMeasureHeader: Equatable, Sendable {
    var numerator = 4
    var denominator = 4
    var isRepeatOpen = false
    /// 0 = no repeat sign; otherwise how many times the section plays in all.
    var repeatClose = 0
    /// Bitmask of alternate endings this measure belongs to (bit 0 = first ending); 0 = every pass.
    var repeatAlternative = 0
    var marker: String?
    /// Tempo at the start of the measure when the file says so (GP5 stores it per beat; the first beat's wins).
    var tempo: Int?

    var ticks: Int { numerator * TabScore.ticksPerQuarter * 4 / max(denominator, 1) }
}

nonisolated struct TabTrack: Equatable, Sendable {
    var name = ""
    /// Open-string MIDI pitches, string 1 (highest) first, as Guitar Pro stores them.
    var tunings: [UInt8] = []
    var capo = 0
    var isPercussion = false
    /// General MIDI program 0–127.
    var program = 0
    /// MIDI channel 0–15 (9 = drums).
    var channel = 0
    var volume: UInt8 = 100
    var measures: [TabMeasure] = []

    var stringCount: Int { tunings.count }
    /// "E2 A2 D3 G3 B3 E4" style, lowest first, for `Tuning`.
    var tuningDescription: String { tunings.reversed().map { TabScore.noteName($0) }.joined(separator: " ") }
}

nonisolated struct TabMeasure: Equatable, Sendable {
    /// Guitar Pro 5 has two voices per measure.
    var voices: [[TabBeat]] = [[], []]
}

nonisolated struct TabBeat: Equatable, Sendable {
    /// Ticks from the start of the measure.
    var start = 0
    var duration = TabScore.ticksPerQuarter
    var isRest = false
    var notes: [TabNote] = []
    /// A tempo change at this beat.
    var tempo: Int?
    var text: String?
    var chordName: String?
}

nonisolated struct TabNote: Equatable, Sendable {
    struct Effects: OptionSet, Sendable, Equatable {
        let rawValue: UInt16
        static let bend = Effects(rawValue: 1 << 0)
        static let slide = Effects(rawValue: 1 << 1)
        static let hammerOn = Effects(rawValue: 1 << 2)
        static let palmMute = Effects(rawValue: 1 << 3)
        static let letRing = Effects(rawValue: 1 << 4)
        static let vibrato = Effects(rawValue: 1 << 5)
        static let harmonic = Effects(rawValue: 1 << 6)
        static let tremolo = Effects(rawValue: 1 << 7)
        static let staccato = Effects(rawValue: 1 << 8)
        static let ghost = Effects(rawValue: 1 << 9)
        static let accent = Effects(rawValue: 1 << 10)
    }

    /// 1 = highest string.
    var string: Int
    var fret: Int
    /// Tied to the previous note: sounds on, not struck again.
    var isTie = false
    /// Dead (muted) note: a click, no pitch.
    var isDead = false
    var velocity: UInt8 = 95
    var effects: Effects = []
}

nonisolated extension TabScore {
    /// "E2", "F♯3": note name with octave, for tuning text.
    static func noteName(_ pitch: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[Int(pitch) % 12])\(Int(pitch) / 12 - 1)"
    }
}
