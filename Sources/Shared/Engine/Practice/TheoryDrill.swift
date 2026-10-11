import Foundation
import MusicTheoryKit

/// Theory flashcards generated from the theory engine: "the major 3rd of D?", "which note isn't in A Dorian?",
/// "the IV chord of G major?", "which degree is F♯ in D major?". Pure and seeded; the view model asks and grades.
nonisolated enum TheoryDrill {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case intervalNote, scaleNote, keyChord, degree

        var id: String { rawValue }
        var title: String {
            switch self {
            case .intervalNote: "Intervals"
            case .scaleNote: "Scales"
            case .keyChord: "Chords in a key"
            case .degree: "Degrees"
            }
        }
    }

    struct Question: Equatable, Sendable, Identifiable {
        var id: Int
        var kind: Kind
        var prompt: String
        /// Answers to show; for `.intervalNote` the twelve note names (the note grid), else these buttons.
        var choices: [String]
        var answer: Int
        /// Card key, stable across sessions: "theory:interval:M3", "theory:scale:dorian", "theory:chord:IV",
        /// "theory:degree:6".
        var key: String
        /// The note grid answers by pitch class rather than index.
        var answerPitchClass: Int?
    }

    enum Verdict: Equatable, Sendable { case correct, wrong(chosen: Int) }

    static let questionsPerRound = 12
    static let thresholds = AutoGrade.Thresholds(fast: 3, slow: 8)
    static let intervalsAsked: [Interval] = [.minorSecond, .majorSecond, .minorThird, .majorThird, .perfectFourth, .tritone, .perfectFifth, .minorSixth, .majorSixth, .minorSeventh, .majorSeventh]
    static let scalesAsked: [Scale.Kind] = [.major, .naturalMinor, .majorPentatonic, .minorPentatonic, .blues, .mode(.dorian), .mode(.mixolydian), .mode(.lydian), .mode(.phrygian), .harmonicMinor]
    static let numerals = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
    static let minorNumerals = ["i", "ii°", "III", "iv", "v", "VI", "VII"]

    static func questions(kind: Kind, count: Int, seed: UInt64, preferSharps: Bool, dueKeys: [String] = []) -> [Question] {
        var random = SplitMixRandom(state: seed)
        return (0..<count).map { index in
            question(id: index, kind: kind, dueKey: index < dueKeys.count ? dueKeys[index] : nil, preferSharps: preferSharps, random: &random)
        }
    }

    static func question(id: Int, kind: Kind, dueKey: String? = nil, preferSharps: Bool, random: inout SplitMixRandom) -> Question {
        func pick<T>(_ options: [T]) -> T { options[Int(random.nextUnit() * Double(options.count)) % options.count] }
        func name(_ pitchClass: Int, sharps: Bool = preferSharps) -> String { PitchName.name(forPitchClass: (pitchClass % 12 + 12) % 12, preferSharps: sharps) }
        let root = Int(random.nextUnit() * 12) % 12
        switch kind {
        case .intervalNote:
            let interval = intervalsAsked.first { "theory:interval:\($0.shortName)" == dueKey } ?? pick(intervalsAsked)
            let target = (root + interval.semitones) % 12
            return Question(id: id, kind: kind, prompt: "The \(interval.name.lowercased()) above \(name(root))?", choices: [], answer: target,
                            key: "theory:interval:\(interval.shortName)", answerPitchClass: target)
        case .scaleNote:
            let scaleKind = scalesAsked.first { "theory:scale:\(ScaleShapes.kindKey($0))" == dueKey } ?? pick(scalesAsked)
            let scale = Scale(root: root, kind: scaleKind)
            let sharps = !scaleKind.isMinorish && preferSharps || (scaleKind.isMinorish && preferSharps && [9, 4, 11, 6, 1].contains(root))
            // Three notes that are in the scale and one that isn't.
            let inside = scale.pitchClasses.filter { $0 != root }.shuffled(using: &random).prefix(3)
            let outside = pick((0..<12).filter { !scale.contains(pitchClass: $0) })
            let choices = (Array(inside) + [outside]).shuffled(using: &random)
            return Question(id: id, kind: kind, prompt: "Which note is not in \(scale.name(preferSharps: sharps))?", choices: choices.map { name($0, sharps: sharps) },
                            answer: choices.firstIndex(of: outside) ?? 0, key: "theory:scale:\(ScaleShapes.kindKey(scaleKind))")
        case .keyChord:
            let degrees = Array(0..<7)
            // A due key says which mode it came from; otherwise minor keys come up about a third of the time.
            let dueIsMajor = dueKey.map { key in numerals.contains { "theory:chord:\($0)" == key } } ?? false
            let dueIsMinor = dueKey.map { key in minorNumerals.contains { "theory:chord:\($0)" == key } } ?? false
            let isMinor = dueIsMinor || (!dueIsMajor && random.nextUnit() < 0.3)
            let degree = degrees.first { "theory:chord:\(isMinor ? minorNumerals[$0] : numerals[$0])" == dueKey } ?? pick(degrees)
            let scale = Scale(root: root, kind: isMinor ? .naturalMinor : .major)
            let classes = scale.pitchClasses
            let chordRoot = classes[degree]
            let chord = Chord(root: chordRoot, quality: diatonicQuality(degree: degree, isMinor: isMinor))
            let sharps = preferSharps ? 1 : -1
            let answer = chord.name(sharps: sharps)
            // Distractors: the same root with other qualities, and neighbouring diatonic chords.
            var others: [String] = []
            for quality in [Chord.Quality.major, .minor, .diminished] where quality != chord.quality { others.append(Chord(root: chordRoot, quality: quality).name(sharps: sharps)) }
            for other in degrees where other != degree { others.append(Chord(root: classes[other], quality: diatonicQuality(degree: other, isMinor: isMinor)).name(sharps: sharps)) }
            let distractors = Array(others.shuffled(using: &random).prefix(3))
            let choices = ([answer] + distractors).shuffled(using: &random)
            let numeral = isMinor ? minorNumerals[degree] : numerals[degree]
            return Question(id: id, kind: kind, prompt: "The \(numeral) chord of \(name(root, sharps: preferSharps)) \(isMinor ? "minor" : "major")?", choices: choices,
                            answer: choices.firstIndex(of: answer) ?? 0, key: "theory:chord:\(numeral)")
        case .degree:
            let degrees = Array(1...7)
            let degree = degrees.first { "theory:degree:\($0)" == dueKey } ?? pick(degrees)
            let scale = Scale(root: root, kind: .major)
            let note = scale.pitchClasses[degree - 1]
            return Question(id: id, kind: kind, prompt: "Which degree is \(name(note)) in \(name(root)) major?", choices: degrees.map { "\($0)" },
                            answer: degree - 1, key: "theory:degree:\(degree)")
        }
    }

    /// Triad quality on each degree of the major or natural minor scale.
    static func diatonicQuality(degree: Int, isMinor: Bool) -> Chord.Quality {
        let major: [Chord.Quality] = [.major, .minor, .minor, .major, .major, .minor, .diminished]
        let minor: [Chord.Quality] = [.minor, .diminished, .major, .minor, .minor, .major, .major]
        return (isMinor ? minor : major)[degree % 7]
    }

    static func grade(_ question: Question, chosen: Int) -> Verdict {
        if let pitchClass = question.answerPitchClass { return chosen == pitchClass ? .correct : .wrong(chosen: chosen) }
        return chosen == question.answer ? .correct : .wrong(chosen: chosen)
    }
}

nonisolated private extension Array {
    func shuffled(using random: inout SplitMixRandom) -> [Element] {
        var copy = self
        for index in stride(from: copy.count - 1, to: 0, by: -1) {
            let other = Int(random.nextUnit() * Double(index + 1)) % (index + 1)
            copy.swapAt(index, other)
        }
        return copy
    }
}
