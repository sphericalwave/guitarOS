import Foundation

/// The bundled voicings: the open chords everyone learns first, the two barre shapes, power chords, and
/// a few colours. Static content lives in code, not in the store.
nonisolated enum ChordLibrary {
    static let voicings: [ChordVoicing] = [
        // Open
        v("C", [nil, 3, 2, 0, 1, 0], [nil, 3, 2, nil, 1, nil], .open),
        v("A", [nil, 0, 2, 2, 2, 0], [nil, nil, 1, 2, 3, nil], .open),
        v("G", [3, 2, 0, 0, 0, 3], [2, 1, nil, nil, nil, 3], .open),
        v("E", [0, 2, 2, 1, 0, 0], [nil, 2, 3, 1, nil, nil], .open),
        v("D", [nil, nil, 0, 2, 3, 2], [nil, nil, nil, 1, 3, 2], .open),
        v("Am", [nil, 0, 2, 2, 1, 0], [nil, nil, 2, 3, 1, nil], .open),
        v("Em", [0, 2, 2, 0, 0, 0], [nil, 2, 3, nil, nil, nil], .open),
        v("Dm", [nil, nil, 0, 2, 3, 1], [nil, nil, nil, 2, 3, 1], .open),
        v("F", [1, 3, 3, 2, 1, 1], [1, 3, 4, 2, 1, 1], .open, barre: 1),
        v("Fmaj7", [nil, nil, 3, 2, 1, 0], [nil, nil, 3, 2, 1, nil], .open),
        // Sevenths
        v("E7", [0, 2, 0, 1, 0, 0], [nil, 2, nil, 1, nil, nil], .seventh),
        v("A7", [nil, 0, 2, 0, 2, 0], [nil, nil, 2, nil, 3, nil], .seventh),
        v("D7", [nil, nil, 0, 2, 1, 2], [nil, nil, nil, 2, 1, 3], .seventh),
        v("G7", [3, 2, 0, 0, 0, 1], [3, 2, nil, nil, nil, 1], .seventh),
        v("C7", [nil, 3, 2, 3, 1, 0], [nil, 3, 2, 4, 1, nil], .seventh),
        v("B7", [nil, 2, 1, 2, 0, 2], [nil, 2, 1, 3, nil, 4], .seventh),
        v("Am7", [nil, 0, 2, 0, 1, 0], [nil, nil, 2, nil, 1, nil], .seventh),
        v("Em7", [0, 2, 0, 0, 0, 0], [nil, 2, nil, nil, nil, nil], .seventh),
        v("Dm7", [nil, nil, 0, 2, 1, 1], [nil, nil, nil, 2, 1, 1], .seventh),
        v("Cmaj7", [nil, 3, 2, 0, 0, 0], [nil, 3, 2, nil, nil, nil], .seventh),
        v("Amaj7", [nil, 0, 2, 1, 2, 0], [nil, nil, 2, 1, 3, nil], .seventh),
        v("Dmaj7", [nil, nil, 0, 2, 2, 2], [nil, nil, nil, 1, 1, 1], .seventh),
        // Colour
        v("Cadd9", [nil, 3, 2, 0, 3, 0], [nil, 2, 1, nil, 3, nil], .colour),
        v("Asus2", [nil, 0, 2, 2, 0, 0], [nil, nil, 1, 2, nil, nil], .colour),
        v("Dsus2", [nil, nil, 0, 2, 3, 0], [nil, nil, nil, 1, 3, nil], .colour),
        v("Dsus4", [nil, nil, 0, 2, 3, 3], [nil, nil, nil, 1, 2, 3], .colour),
        v("Esus4", [0, 2, 2, 2, 0, 0], [nil, 1, 2, 3, nil, nil], .colour),
        v("G/B", [nil, 2, 0, 0, 0, 3], [nil, 1, nil, nil, nil, 3], .colour),
        // E-shape barres
        v("F♯m", [2, 4, 4, 2, 2, 2], [1, 3, 4, 1, 1, 1], .barreE, barre: 2),
        v("G (barre)", [3, 5, 5, 4, 3, 3], [1, 3, 4, 2, 1, 1], .barreE, barre: 3),
        v("Gm", [3, 5, 5, 3, 3, 3], [1, 3, 4, 1, 1, 1], .barreE, barre: 3),
        v("A (barre)", [5, 7, 7, 6, 5, 5], [1, 3, 4, 2, 1, 1], .barreE, barre: 5),
        v("B (barre)", [7, 9, 9, 8, 7, 7], [1, 3, 4, 2, 1, 1], .barreE, barre: 7),
        // A-shape barres
        v("B♭", [nil, 1, 3, 3, 3, 1], [nil, 1, 2, 3, 4, 1], .barreA, barre: 1),
        v("B", [nil, 2, 4, 4, 4, 2], [nil, 1, 2, 3, 4, 1], .barreA, barre: 2),
        v("Bm", [nil, 2, 4, 4, 3, 2], [nil, 1, 3, 4, 2, 1], .barreA, barre: 2),
        v("C♯m", [nil, 4, 6, 6, 5, 4], [nil, 1, 3, 4, 2, 1], .barreA, barre: 4),
        v("D (barre)", [nil, 5, 7, 7, 7, 5], [nil, 1, 2, 3, 4, 1], .barreA, barre: 5),
        // Power chords
        v("E5", [0, 2, 2, nil, nil, nil], [nil, 1, 2, nil, nil, nil], .power),
        v("A5", [nil, 0, 2, 2, nil, nil], [nil, nil, 1, 2, nil, nil], .power),
        v("D5", [nil, nil, 0, 2, 3, nil], [nil, nil, nil, 1, 2, nil], .power),
        v("G5", [3, 5, 5, nil, nil, nil], [1, 3, 4, nil, nil, nil], .power),
        v("C5", [nil, 3, 5, 5, nil, nil], [nil, 1, 3, 4, nil, nil], .power),
    ]

    static func voicing(named name: String) -> ChordVoicing? {
        voicings.first { $0.name == name }
    }

    /// The pair a beginner starts with; the routine uses it until the player has a weakest pair.
    static let defaultPair = ("C", "G")

    private static func v(_ name: String, _ frets: [Int?], _ fingers: [Int?], _ family: ChordVoicing.Family, barre: Int? = nil) -> ChordVoicing {
        ChordVoicing(name: name, frets: frets, fingers: fingers, barre: barre, family: family)
    }
}
