import Foundation
import MusicTheoryKit
import PitchKit

/// The fretboard note trainer's pure parts: which positions are in play, what to ask, and how an answer
/// is judged. The view model wires these to the mic and the card store.
nonisolated enum FretboardDrill {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// "Play F♯ on the G string": the mic grades it.
        case findTheNote
        /// A dot is shown; tap its name. Silent.
        case nameTheNote

        var id: String { rawValue }
        var title: String {
            switch self {
            case .findTheNote: "Play it"
            case .nameTheNote: "Name it"
            }
        }
        var icon: String {
            switch self {
            case .findTheNote: "mic"
            case .nameTheNote: "hand.tap"
            }
        }
    }

    /// Which part of the neck is in play. The default is the whole first octave on every string.
    struct Scope: Equatable, Sendable, Codable {
        var strings: ClosedRange<Int> = 1...6
        var frets: ClosedRange<Int> = 0...12
        var naturalsOnly = true

        static let `default` = Scope()
    }

    struct Prompt: Equatable, Sendable, Identifiable {
        var position: FretPosition
        var pitch: UInt8
        var id: String { position.key }
        var pitchClass: Int { Int(pitch) % 12 }
    }

    enum Verdict: Equatable, Sendable {
        case correct
        /// What was heard (or tapped) instead, as a MIDI pitch for the mic, a pitch class for taps.
        case wrong(heardPitch: Int?)
    }

    /// Card key for a position in a tuning: "fret:E2 A2 D3 G3 B3 E4:s3f7". The tuning is part of the key
    /// because the same dot is a different note in drop D.
    static func cardKey(position: FretPosition, tuning: Tuning) -> String {
        "fret:\(tuning.description):\(position.key)"
    }

    static func position(fromCardKey key: String) -> FretPosition? {
        key.split(separator: ":").last.flatMap { FretPosition(key: String($0)) }
    }

    /// Builds a sitting: due cards in scope first (most overdue first), then unseen positions, shuffled with
    /// a seed so tests are repeatable. `count` caps the sitting.
    static func queue(
        fretboard: Fretboard,
        scope: Scope,
        dueKeys: [String],
        seenKeys: Set<String>,
        count: Int = 12,
        seed: UInt64 = UInt64(Date.now.timeIntervalSince1970)
    ) -> [Prompt] {
        let inScope = fretboard.allPositions(frets: scope.frets, strings: scope.strings, naturalsOnly: scope.naturalsOnly)
        let keyOf = { (p: FretPosition) in cardKey(position: p, tuning: fretboard.tuning) }
        let due = dueKeys.compactMap(position(fromCardKey:)).filter { inScope.contains($0) }
        var generator = SeededGenerator(seed: seed)
        let fresh = inScope.filter { !seenKeys.contains(keyOf($0)) && !due.contains($0) }.shuffled(using: &generator)
        let rest = inScope.filter { seenKeys.contains(keyOf($0)) && !due.contains($0) }.shuffled(using: &generator)
        return (due + fresh + rest).prefix(count).map { Prompt(position: $0, pitch: fretboard.pitch(at: $0)) }
    }

    /// Mic answer: the heard note must be the exact pitch asked (the string is trusted). The reference A
    /// matters here: a 432-tuned guitar at A440 would read a third of a semitone flat.
    static func judge(prompt: Prompt, heardFrequency: Double, referenceA: Double) -> Verdict {
        let nearest = PitchMath.note(nearest: heardFrequency, a4: referenceA)
        guard abs(nearest.cents) <= 35 else { return .wrong(heardPitch: nil) }
        return nearest.note == Int(prompt.pitch) ? .correct : .wrong(heardPitch: nearest.note)
    }

    /// Tap answer: the name is right if the pitch class matches.
    static func judge(prompt: Prompt, tappedPitchClass: Int) -> Verdict {
        tappedPitchClass == prompt.pitchClass ? .correct : .wrong(heardPitch: tappedPitchClass)
    }

    /// A heard pitch has to hold for this many consecutive readings before it's judged, so the attack and
    /// a bend into the note don't count against the player.
    static let stableReadings = 3

    /// Where a wrongly played note lives on the asked string, to show "you played this".
    static func heardPosition(pitch: Int, onString string: Int, fretboard: Fretboard) -> FretPosition? {
        guard let value = UInt8(exactly: pitch) else { return nil }
        return fretboard.positions(of: value).first { $0.string == string }
    }
}

/// SplitMix64, so shuffles are repeatable in tests.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
