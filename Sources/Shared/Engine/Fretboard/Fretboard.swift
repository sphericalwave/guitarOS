import Foundation
import MusicTheoryKit

/// Pitch ↔ position on a neck with a given tuning and fret count.
nonisolated struct Fretboard: Hashable, Sendable {
    var tuning: Tuning
    /// Highest fret on the neck. Most electrics have 22 or 24, acoustics 20.
    var fretCount: Int

    init(tuning: Tuning = .standard, fretCount: Int = 22) {
        self.tuning = tuning
        self.fretCount = fretCount
    }

    var strings: ClosedRange<Int> { 1...tuning.stringCount }
    var frets: ClosedRange<Int> { 0...fretCount }

    func pitch(at position: FretPosition) -> UInt8 {
        tuning.pitch(string: position.string, fret: position.fret)
    }

    func pitchClass(at position: FretPosition) -> Int {
        Int(pitch(at: position)) % 12
    }

    /// Every place this exact pitch lives, lowest string first. E4 is open 1, 2nd string 5, 3rd string 9...
    func positions(of pitch: UInt8, frets range: ClosedRange<Int>? = nil) -> [FretPosition] {
        let range = range ?? frets
        return strings.reversed().compactMap { string in
            let fret = Int(pitch) - Int(tuning.openPitch(string: string))
            return range.contains(fret) && frets.contains(fret) ? FretPosition(string: string, fret: fret) : nil
        }
    }

    /// Every place a pitch class lives within a fret range, in reading order.
    func positions(ofPitchClass pitchClass: Int, frets range: ClosedRange<Int>? = nil, strings: ClosedRange<Int>? = nil) -> [FretPosition] {
        let range = range ?? frets
        let strings = strings ?? self.strings
        var result: [FretPosition] = []
        for string in strings.reversed() {
            for fret in range where frets.contains(fret) {
                let position = FretPosition(string: string, fret: fret)
                if self.pitchClass(at: position) == (pitchClass % 12 + 12) % 12 { result.append(position) }
            }
        }
        return result
    }

    /// All positions within a range, in reading order. What the note trainer draws cards from.
    func allPositions(frets range: ClosedRange<Int>? = nil, strings: ClosedRange<Int>? = nil, naturalsOnly: Bool = false) -> [FretPosition] {
        let range = range ?? frets
        let strings = strings ?? self.strings
        return strings.reversed().flatMap { string in
            range.filter { frets.contains($0) }.map { FretPosition(string: string, fret: $0) }
        }.filter { !naturalsOnly || Scale(root: 0, kind: .major).contains(pitchClass: pitchClass(at: $0)) }
    }

    /// Lowest and highest pitch on the neck, for detector ranges.
    var pitchRange: ClosedRange<UInt8> {
        tuning.openPitches.min()!...tuning.pitch(string: 1, fret: fretCount)
    }
}
