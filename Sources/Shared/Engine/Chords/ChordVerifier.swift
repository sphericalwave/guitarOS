import Foundation
import PitchKit

/// What one strum sounded like against the voicing the drill asked for. Per string, so the grid can light
/// the one that didn't ring.
nonisolated struct ChordVerdict: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// Every expected string was heard.
        case clean
        /// Most of the chord was there; `missing` says which strings weren't.
        case partial
        /// Little or none of the chord was heard.
        case wrong
    }

    var outcome: Outcome
    /// Strings (1 = high E) that were expected but not heard.
    var missing: [Int]
    /// Pitches heard a fret or two from an expected note that aren't the chord's own: a wrong fret.
    var unexpected: [UInt8]
    /// Host-clock time of the strum's first note-on.
    var time: TimeInterval

    var isClean: Bool { outcome == .clean }
}

/// Score-informed chord checking: the app knows which voicing it asked for, so it verifies the strings it
/// expects instead of transcribing the strum. The notes heard come from `StrumAnalyzer`, which scores only
/// the voicings in play.
///
/// Octave doublings (open C has C3 + C4 and E3 + E4) are the hard case for any template estimator, so a pitch
/// class that the voicing doubles counts as heard once any octave of it is; the bass string is checked exactly.
nonisolated enum ChordVerifier {
    /// Below this share of expected strings the strum is a different chord, not a flawed one.
    static let partialShare = 0.5

    static func verdict(heard: Set<UInt8>, expected voicing: ChordVoicing, tuning: Tuning = .standard, time: TimeInterval = 0) -> ChordVerdict {
        let strings = expectedStrings(voicing, tuning: tuning)
        guard !strings.isEmpty else { return ChordVerdict(outcome: .wrong, missing: [], unexpected: heard.sorted(), time: time) }
        let expectedPitches = Set(strings.map(\.pitch))
        let doubledClasses = Dictionary(grouping: strings, by: { $0.pitch % 12 }).filter { $0.value.count > 1 }.keys
        let heardClasses = Set(heard.map { $0 % 12 })
        let bass = strings.map(\.pitch).min()!

        var missing: [Int] = []
        for string in strings {
            if heard.contains(string.pitch) { continue }
            // A doubled note heard in either octave is that note; the bass has to be there itself.
            if string.pitch != bass, doubledClasses.contains(string.pitch % 12), heardClasses.contains(string.pitch % 12) { continue }
            missing.append(string.string)
        }
        // Only a fret or two off an expected note is reported: the pick's transient and the strings' upper
        // overtones throw up high phantoms that say nothing about the hand.
        let unexpected = heard.filter { pitch in
            !expectedPitches.contains(pitch) && !heardClassIsExpected(pitch, expectedPitches: expectedPitches)
                && expectedPitches.contains { abs(Int($0) - Int(pitch)) <= 2 }
        }.sorted()

        let share = Double(strings.count - missing.count) / Double(strings.count)
        let outcome: ChordVerdict.Outcome = missing.isEmpty ? .clean : (share >= partialShare ? .partial : .wrong)
        return ChordVerdict(outcome: outcome, missing: missing.sorted(), unexpected: unexpected, time: time)
    }

    /// Expected (string, pitch) pairs from the voicing, 1 = high E.
    static func expectedStrings(_ voicing: ChordVoicing, tuning: Tuning) -> [(string: Int, pitch: UInt8)] {
        voicing.frets.enumerated().compactMap { index, fret in
            guard let fret, index < tuning.stringCount else { return nil }
            let string = tuning.stringCount - index
            return (string, tuning.pitch(string: string, fret: fret))
        }
    }

    /// An octave of an expected note, or a note sitting on an expected note's overtone, is the chord itself heard
    /// imperfectly, not a wrong fret.
    private static func heardClassIsExpected(_ pitch: UInt8, expectedPitches: Set<UInt8>) -> Bool {
        expectedPitches.contains { expected in
            pitch % 12 == expected % 12 || PolyphonicNoteEstimator.isHarmonicGhost(pitch, of: expected)
        }
    }
}

/// Counts one-minute changes from strums: alternating between the pair, a change is counted when the chord
/// the hand should be moving to is heard clean. Strumming the chord already held again isn't a change.
nonisolated struct ChordChangeCounter: Sendable {
    struct Feedback: Equatable, Sendable {
        /// Against the chord the player was moving to.
        var verdict: ChordVerdict
        /// The chord that was heard clean, if either was.
        var heard: String?
        var counted: Bool
    }

    let first: ChordVoicing
    let second: ChordVoicing
    let tuning: Tuning
    private(set) var changes = 0
    private(set) var strums = 0

    init(first: ChordVoicing, second: ChordVoicing, tuning: Tuning = .standard) {
        self.first = first
        self.second = second
        self.tuning = tuning
    }

    /// Chord held now (first until the first change, then alternating).
    var current: ChordVoicing { changes % 2 == 0 ? first : second }
    /// Chord the hand is moving to.
    var next: ChordVoicing { changes % 2 == 0 ? second : first }

    mutating func strum(_ pitches: Set<UInt8>, at time: TimeInterval) -> Feedback {
        strums += 1
        let target = next
        let toNext = ChordVerifier.verdict(heard: pitches, expected: target, tuning: tuning, time: time)
        if toNext.isClean {
            changes += 1
            return Feedback(verdict: toNext, heard: target.name, counted: true)
        }
        let toCurrent = ChordVerifier.verdict(heard: pitches, expected: current, tuning: tuning, time: time)
        return Feedback(verdict: toNext, heard: toCurrent.isClean ? current.name : nil, counted: false)
    }

    mutating func reset() {
        changes = 0
        strums = 0
    }
}
