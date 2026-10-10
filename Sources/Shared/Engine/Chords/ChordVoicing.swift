import Foundation
import MusicTheoryKit

/// One way to play a chord: a fret per string (nil = muted), low string first, plus fingering hints.
nonisolated struct ChordVoicing: Hashable, Sendable, Identifiable, Codable {
    var name: String
    /// Frets from string 6 to string 1; 0 is open, nil is muted.
    var frets: [Int?]
    /// Fingers 1–4 per string (nil for open/muted), same order as `frets`.
    var fingers: [Int?]?
    /// Fret a barre covers, if any.
    var barre: Int?
    /// Group for the library list.
    var family: Family

    enum Family: String, CaseIterable, Sendable, Codable {
        case open, barreE, barreA, power, seventh, colour

        var title: String {
            switch self {
            case .open: "Open chords"
            case .barreE: "E-shape barres"
            case .barreA: "A-shape barres"
            case .power: "Power chords"
            case .seventh: "Sevenths"
            case .colour: "Colour chords"
            }
        }
    }

    var id: String { name }

    /// Lowest fretted position (1 if everything is open), where the grid starts.
    var baseFret: Int {
        let fretted = frets.compactMap { $0 }.filter { $0 > 0 }
        guard let lowest = fretted.min(), let highest = fretted.max() else { return 1 }
        return highest <= 4 ? 1 : lowest
    }

    /// MIDI pitches sounding in a tuning, lowest string first.
    func pitches(in tuning: Tuning = .standard) -> [UInt8] {
        zip(frets, tuning.openPitches).compactMap { fret, open in fret.map { UInt8(clamping: Int(open) + $0) } }
    }

    /// Stable key for pairs: "C" and "G" → "change:C>G" regardless of order? No — a change has a direction
    /// in the hand but the drill alternates, so pairs are unordered and sorted.
    static func changeKey(_ a: ChordVoicing, _ b: ChordVoicing) -> String {
        let names = [a.name, b.name].sorted()
        return "change:\(names[0])>\(names[1])"
    }
}
