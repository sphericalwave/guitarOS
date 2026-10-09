import Foundation
import MusicTheoryKit

/// The open-string pitches of a guitar, lowest string first.
/// Strings are numbered the way guitarists count them: 1 is the thinnest (high E), 6 the thickest.
nonisolated struct Tuning: Hashable, Sendable, Codable {
    var name: String
    /// MIDI pitches from the lowest (thickest) string up.
    var openPitches: [UInt8]

    var stringCount: Int { openPitches.count }

    /// Open pitch of a string by guitarist number (1 = highest).
    func openPitch(string: Int) -> UInt8 {
        openPitches[stringCount - string]
    }

    /// Pitch at a fret on a string; fret 0 is the open string.
    func pitch(string: Int, fret: Int) -> UInt8 {
        UInt8(clamping: Int(openPitch(string: string)) + fret)
    }

    /// "E2 A2 D3 G3 B3 E4" — stable text for settings and sync.
    var description: String {
        openPitches.map { PitchName.name(for: $0) }.joined(separator: " ")
    }

    /// Parses `description` form; nil if any note is unreadable or there are fewer than 4 strings.
    init?(description: String, name: String = "Custom") {
        let pitches = description.split(separator: " ").compactMap { Tuning.pitch(named: String($0)) }
        guard pitches.count >= 4, pitches.count == description.split(separator: " ").count else { return nil }
        self.init(name: name, openPitches: pitches)
    }

    init(name: String, openPitches: [UInt8]) {
        self.name = name
        self.openPitches = openPitches
    }

    static let standard = Tuning(name: "Standard", openPitches: [40, 45, 50, 55, 59, 64])
    static let dropD = Tuning(name: "Drop D", openPitches: [38, 45, 50, 55, 59, 64])
    static let halfStepDown = Tuning(name: "Half step down", openPitches: [39, 44, 49, 54, 58, 63])
    static let dadgad = Tuning(name: "DADGAD", openPitches: [38, 45, 50, 55, 57, 62])
    static let openG = Tuning(name: "Open G", openPitches: [38, 43, 50, 55, 59, 62])
    static let openD = Tuning(name: "Open D", openPitches: [38, 45, 50, 54, 57, 62])

    /// Standard first (the default), then the common alternates.
    static let presets: [Tuning] = [.standard, .dropD, .halfStepDown, .dadgad, .openG, .openD]

    /// The preset with these pitches, or a custom tuning.
    static func named(description: String) -> Tuning? {
        guard let parsed = Tuning(description: description) else { return nil }
        return presets.first { $0.openPitches == parsed.openPitches } ?? parsed
    }

    /// "E2", "F♯3", "Bb3", "C#4" → MIDI.
    private static func pitch(named text: String) -> UInt8? {
        var chars = Array(text)
        guard let letter = chars.first, let index = "CDEFGAB".firstIndex(of: letter) else { return nil }
        chars.removeFirst()
        var alteration = 0
        while let c = chars.first, "♯#".contains(c) || "♭b".contains(c) {
            alteration += "♯#".contains(c) ? 1 : -1
            chars.removeFirst()
        }
        guard let octave = Int(String(chars)) else { return nil }
        let natural = [0, 2, 4, 5, 7, 9, 11]["CDEFGAB".distance(from: "CDEFGAB".startIndex, to: index)]
        let midi = (octave + 1) * 12 + natural + alteration
        guard (0...127).contains(midi) else { return nil }
        return UInt8(midi)
    }
}
