import Foundation
import MusicTheoryKit

/// Ear training questions: intervals, chord qualities, scale degrees in a key, and short phrases to play back.
/// Pure: questions are generated from a seed, answers graded here, sound and input handled by the view model.
nonisolated enum EarDrill {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case interval, chordQuality, scaleDegree, playBack

        var id: String { rawValue }
        var title: String {
            switch self {
            case .interval: "Intervals"
            case .chordQuality: "Chords"
            case .scaleDegree: "Degrees"
            case .playBack: "Play it back"
            }
        }
        var prompt: String {
            switch self {
            case .interval: "Which interval?"
            case .chordQuality: "Which chord?"
            case .scaleDegree: "Which degree?"
            case .playBack: "Play what you heard"
            }
        }
        var kind: DrillKind {
            switch self {
            case .interval: .interval
            case .chordQuality: .chordShape
            case .scaleDegree, .playBack: .theory
            }
        }
    }

    /// One thing to answer: what sounds (`pitches`, `spacing` apart), the right answer, and the choices.
    struct Question: Equatable, Sendable, Identifiable {
        var id: Int
        var mode: Mode
        /// What to play, in order; a tonic-first context for degrees.
        var pitches: [UInt8]
        /// Seconds between notes; 0 plays a block chord.
        var spacing: TimeInterval
        /// Index into `choices`, or for play-back the pitches to hear back are `pitches`.
        var answer: Int
        var choices: [String]
        /// Card key: "ear:interval:P5", "ear:chord:m7", "ear:degree:4", "ear:playback:3".
        var key: String
    }

    enum Verdict: Equatable, Sendable { case correct, wrong(chosen: Int) }

    /// Intervals asked, from easy to hard; the pool grows with `level` (1...4).
    static let intervalLevels: [[Interval]] = [
        [.perfectFifth, .octave, .majorThird, .perfectFourth],
        [.minorThird, .majorSecond, .majorSixth, .minorSeventh],
        [.minorSecond, .tritone, .minorSixth, .majorSeventh],
        [.unison],
    ]
    static let chordLevels: [[Chord.Quality]] = [
        [.major, .minor],
        [.diminished, .augmented],
        [.dominant7, .major7, .minor7],
        [.sus2, .sus4, .halfDiminished7, .diminished7],
    ]
    /// Comfortable guitar register for reference tones.
    static let register: ClosedRange<UInt8> = 48...72

    static func intervals(level: Int) -> [Interval] { intervalLevels.prefix(max(1, min(level, intervalLevels.count))).flatMap { $0 } }
    static func qualities(level: Int) -> [Chord.Quality] { chordLevels.prefix(max(1, min(level, chordLevels.count))).flatMap { $0 } }

    /// `count` questions for a mode, reproducible from `seed`. Due keys come first when given.
    static func questions(mode: Mode, level: Int, count: Int, seed: UInt64, dueKeys: [String] = []) -> [Question] {
        var random = SplitMixRandom(state: seed)
        var questions: [Question] = []
        for index in 0..<count {
            let dueKey = index < dueKeys.count ? dueKeys[index] : nil
            questions.append(question(id: index, mode: mode, level: level, dueKey: dueKey, random: &random))
        }
        return questions
    }

    static func question(id: Int, mode: Mode, level: Int, dueKey: String? = nil, random: inout SplitMixRandom) -> Question {
        func pick<T>(_ options: [T]) -> T { options[Int(random.nextUnit() * Double(options.count)) % options.count] }
        let root = UInt8(Int(register.lowerBound) + Int(random.nextUnit() * 13))
        switch mode {
        case .interval:
            let pool = intervals(level: level)
            let interval = pool.first { "ear:interval:\($0.shortName)" == dueKey } ?? pick(pool)
            let ascending = random.nextUnit() < 0.7
            let other = UInt8(clamping: Int(root) + interval.semitones)
            let choices = pool.sorted().map(\.name)
            return Question(id: id, mode: mode, pitches: ascending ? [root, other] : [other, root], spacing: 0.6,
                            answer: choices.firstIndex(of: interval.name) ?? 0, choices: choices, key: "ear:interval:\(interval.shortName)")
        case .chordQuality:
            let pool = qualities(level: level)
            let quality = pool.first { "ear:chord:\($0.symbol)" == dueKey } ?? pick(pool)
            let pitches = quality.intervals.sorted().map { UInt8(clamping: Int(root) + $0) }
            let choices = pool.map(Self.qualityName)
            return Question(id: id, mode: mode, pitches: pitches, spacing: random.nextUnit() < 0.5 ? 0 : 0.25,
                            answer: choices.firstIndex(of: qualityName(quality)) ?? 0, choices: choices, key: "ear:chord:\(quality.symbol)")
        case .scaleDegree:
            let degrees = Array(1...7)
            let degree = degrees.first { "ear:degree:\($0)" == dueKey } ?? pick(degrees)
            let major = Scale.Kind.major.intervals
            // Tonic, then the degree (sometimes an octave up for the upper degrees).
            let target = UInt8(clamping: Int(root) + major[degree - 1])
            let choices = degrees.map { "\($0)" }
            return Question(id: id, mode: mode, pitches: [root, target], spacing: 0.6, answer: degree - 1, choices: choices, key: "ear:degree:\(degree)")
        case .playBack:
            let length = min(2 + level, 5)
            let scale = Scale(root: Int(root) % 12, kind: .majorPentatonic)
            let pool = scale.pitches(in: root...UInt8(clamping: Int(root) + 12))
            var pitches = [root]
            while pitches.count < length {
                let next = pick(pool)
                if next != pitches.last { pitches.append(next) }
            }
            return Question(id: id, mode: mode, pitches: pitches, spacing: 0.5, answer: 0, choices: [], key: "ear:playback:\(length)")
        }
    }

    static func qualityName(_ quality: Chord.Quality) -> String {
        switch quality {
        case .major: "Major"
        case .minor: "Minor"
        case .diminished: "Diminished"
        case .augmented: "Augmented"
        case .sus2: "Sus2"
        case .sus4: "Sus4"
        case .dominant7: "Dominant 7"
        case .major7: "Major 7"
        case .minor7: "Minor 7"
        case .minorMajor7: "Minor-major 7"
        case .halfDiminished7: "Half-diminished"
        case .diminished7: "Diminished 7"
        case .sixth: "6"
        case .minorSixth: "Minor 6"
        }
    }

    static func grade(_ question: Question, chosen: Int) -> Verdict {
        chosen == question.answer ? .correct : .wrong(chosen: chosen)
    }

    /// Play-back: the heard pitch classes have to match the phrase in order; octave is forgiven.
    static func gradePlayBack(_ question: Question, heard: [UInt8]) -> Bool {
        heard.count == question.pitches.count && zip(heard, question.pitches).allSatisfy { $0 % 12 == $1 % 12 }
    }

    static let questionsPerRound = 10
    static let thresholds = AutoGrade.Thresholds(fast: 3, slow: 8)
}
