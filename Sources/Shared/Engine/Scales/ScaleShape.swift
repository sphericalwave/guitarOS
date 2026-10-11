import Foundation
import MusicTheoryKit
import PlayAlongKit

/// One box of a scale on the neck: a four-fret window and every scale note inside it, lowest first.
/// The five windows per scale follow CAGED: each sits where one of the C, A, G, E and D chord shapes of the
/// scale's (relative) major root falls, so position names mean what guitarists expect.
nonisolated struct ScalePosition: Equatable, Sendable, Identifiable {
    var scale: Scale
    var tuning: Tuning
    /// 1...5, low on the neck first.
    var index: Int
    var lowFret: Int
    /// CAGED letter of the chord shape this window sits on.
    var shape: String
    /// Every scale note in the window, ascending by pitch.
    var positions: [FretPosition]

    var id: String { key }
    /// Stable card key: "scale:9:minorPentatonic:1" (root pitch class, kind, position).
    var key: String { "scale:\(scale.root):\(ScaleShapes.kindKey(scale.kind)):\(index)" }
    var frets: ClosedRange<Int> { lowFret...(lowFret + ScaleShapes.span) }
    var title: String { "Position \(index) · \(shape) shape" }

    func pitch(at position: FretPosition) -> UInt8 { tuning.pitch(string: position.string, fret: position.fret) }
    func degree(of position: FretPosition) -> Int? { scale.degree(of: Int(pitch(at: position)) % 12) }
    func isRoot(_ position: FretPosition) -> Bool { Int(pitch(at: position)) % 12 == scale.root }

    /// Up the box and back down, ending on the lowest note.
    var sequence: [FretPosition] { positions + positions.dropLast().reversed() }
}

nonisolated enum ScaleShapes {
    /// Frets above `lowFret` in a window (four frets: one per finger).
    static let span = 3
    /// CAGED shapes with their window offset from the major root's fret on the low E string.
    static let shapes: [(letter: String, offset: Int)] = [("E", -1), ("D", 1), ("C", 4), ("A", 6), ("G", 9)]

    /// The five CAGED positions of a scale, low on the neck first.
    static func caged(_ scale: Scale, tuning: Tuning = .standard) -> [ScalePosition] {
        // Minor-flavoured scales borrow their relative major's shapes (A minor pentatonic uses C major's boxes).
        let majorRoot = scale.kind.isMinorish ? (scale.root + 3) % 12 : scale.root
        let lowString = Int(tuning.openPitch(string: tuning.stringCount)) % 12
        let rootFret = (majorRoot - lowString + 12) % 12
        let windows = shapes.map { shape in (shape.letter, ((rootFret + shape.offset) % 12 + 12) % 12) }
            .sorted { $0.1 < $1.1 }
        return windows.enumerated().map { index, window in
            position(scale, tuning: tuning, lowFret: window.1, index: index + 1, shape: window.0)
        }
    }

    /// Every scale note between `lowFret` and `lowFret + span` on every string, ascending by pitch.
    static func position(_ scale: Scale, tuning: Tuning, lowFret: Int, index: Int, shape: String) -> ScalePosition {
        var positions: [FretPosition] = []
        for string in stride(from: tuning.stringCount, through: 1, by: -1) {
            for fret in lowFret...(lowFret + span) where scale.contains(pitchClass: Int(tuning.pitch(string: string, fret: fret))) {
                positions.append(FretPosition(string: string, fret: fret))
            }
        }
        positions.sort { a, b in
            let pa = tuning.pitch(string: a.string, fret: a.fret), pb = tuning.pitch(string: b.string, fret: b.fret)
            return pa != pb ? pa < pb : a.string > b.string
        }
        return ScalePosition(scale: scale, tuning: tuning, index: index, lowFret: lowFret, shape: shape, positions: positions)
    }

    /// Stable text for a kind, for keys and settings.
    static func kindKey(_ kind: Scale.Kind) -> String {
        switch kind {
        case .major: "major"
        case .naturalMinor: "naturalMinor"
        case .harmonicMinor: "harmonicMinor"
        case .melodicMinor: "melodicMinor"
        case .majorPentatonic: "majorPentatonic"
        case .minorPentatonic: "minorPentatonic"
        case .blues: "blues"
        case .mode(let mode): mode.rawValue
        }
    }

    static func kind(forKey key: String) -> Scale.Kind? {
        Scale.Kind.common.first { kindKey($0) == key }
    }

    /// "scale:9:minorPentatonic:1" → the position, in the tuning given.
    static func position(forKey key: String, tuning: Tuning = .standard) -> ScalePosition? {
        let parts = key.split(separator: ":").map(String.init)
        guard parts.count == 4, parts[0] == "scale", let root = Int(parts[1]), let kind = kind(forKey: parts[2]), let index = Int(parts[3]) else { return nil }
        return caged(Scale(root: root, kind: kind), tuning: tuning).first { $0.index == index }
    }
}

/// Playing a scale position: wait mode (each note when you're ready) or timed (one note per click, judged
/// by PlayAlongKit), with the speed trainer stepping the BPM up after a clean pass.
nonisolated enum ScaleDrill {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case wait, timed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wait: "Wait for me"
            case .timed: "With the click"
            }
        }
    }

    struct Result: Equatable, Sendable {
        var mode: Mode
        var bpm: Double
        var notes: Int
        var hits: Int
        var missed: Int
        /// Timed: presses that matched nothing; wait: wrong notes heard.
        var extras: Int
        var seconds: TimeInterval
        var averageOffset: TimeInterval = 0

        var accuracy: Double { notes == 0 ? 0 : Double(hits) / Double(notes) }
        /// Good enough to speed up.
        var isClean: Bool { accuracy >= ScaleDrill.cleanAccuracy && extras <= notes / 4 }
    }

    static let countInBeats = 4
    static let bpmStep = 5.0
    static let cleanAccuracy = 0.9
    static let defaultBPM = 80.0
    /// Mic readings that have to agree before a note counts, in wait mode.
    static let stableReadings = 2
    /// Ignore the mic this long after a note is cleared: it's still ringing.
    static let settleTime: TimeInterval = 0.2

    /// One note per beat after a one-bar count-in.
    static func expectedNotes(pitches: [UInt8], bpm: Double, countIn: Int = countInBeats) -> [ExpectedNote] {
        let beat = 60 / bpm
        return pitches.enumerated().map { ExpectedNote(id: $0, time: Double(countIn + $0) * beat, pitch: $1) }
    }

    /// Where the speed trainer goes next: up a step after a clean pass, otherwise stay.
    static func nextBPM(after result: Result) -> Double {
        result.isClean ? min(result.bpm + bpmStep, ClickSchedule.bpmRange.upperBound) : result.bpm
    }

    /// SM-2 quality: a clean pass is good or easy, a rough one hard, under half the notes is a fail.
    static func quality(_ result: Result) -> Int {
        if result.isClean { return result.accuracy == 1 && result.extras == 0 ? 5 : 4 }
        return result.accuracy >= 0.5 ? 3 : 1
    }
}
