import Foundation
import Testing
import MusicTheoryKit
@testable import guitar

struct EarDrillTests {
    @Test func questionsAreReproducibleAndWellFormed() {
        let a = EarDrill.questions(mode: .interval, level: 2, count: 10, seed: 42)
        let b = EarDrill.questions(mode: .interval, level: 2, count: 10, seed: 42)
        #expect(a == b && a.count == 10)
        for question in a {
            #expect(question.pitches.count == 2 && question.choices.count == 8)
            #expect(question.choices.indices.contains(question.answer))
            let interval = Interval(from: question.pitches[0], to: question.pitches[1])
            #expect(question.choices[question.answer] == interval.name, "\(question)")
            #expect(question.key == "ear:interval:\(interval.shortName)")
            #expect(question.pitches.allSatisfy { EarDrill.register.contains($0) || $0 <= EarDrill.register.upperBound + 12 })
        }
        #expect(EarDrill.questions(mode: .interval, level: 2, count: 10, seed: 43) != a)
    }

    @Test func levelsGrowThePool() {
        #expect(EarDrill.intervals(level: 1).count == 4 && EarDrill.intervals(level: 3).count == 12 && EarDrill.intervals(level: 9).count == 13)
        #expect(EarDrill.qualities(level: 1) == [.major, .minor] && EarDrill.qualities(level: 3).count == 7)
    }

    @Test func chordQuestionsSoundTheirQuality() {
        for question in EarDrill.questions(mode: .chordQuality, level: 4, count: 20, seed: 7) {
            let root = question.pitches[0]
            let intervals = Set(question.pitches.map { Int($0 - root) })
            let quality = Chord.Quality.allCases.first { $0.intervals == intervals }!
            #expect(question.choices[question.answer] == EarDrill.qualityName(quality))
            #expect(question.key == "ear:chord:\(quality.symbol)")
        }
    }

    @Test func degreeQuestionsPlayTonicThenDegree() {
        for question in EarDrill.questions(mode: .scaleDegree, level: 1, count: 14, seed: 3) {
            let semitones = Int(question.pitches[1]) - Int(question.pitches[0])
            let degree = Scale.Kind.major.intervals.firstIndex(of: semitones)! + 1
            #expect(question.answer == degree - 1 && question.key == "ear:degree:\(degree)")
        }
    }

    @Test func dueKeysComeFirst() {
        let questions = EarDrill.questions(mode: .interval, level: 3, count: 5, seed: 1, dueKeys: ["ear:interval:TT", "ear:interval:m2"])
        #expect(questions[0].key == "ear:interval:TT" && questions[1].key == "ear:interval:m2")
    }

    @Test func playBackPhrasesStayInThePentatonicAndGradeByPitchClass() {
        let question = EarDrill.questions(mode: .playBack, level: 2, count: 1, seed: 5)[0]
        #expect(question.pitches.count == 4 && question.key == "ear:playback:4")
        let scale = Scale(root: Int(question.pitches[0]) % 12, kind: .majorPentatonic)
        #expect(question.pitches.allSatisfy { scale.contains(pitchClass: Int($0) % 12) })
        #expect(EarDrill.gradePlayBack(question, heard: question.pitches.map { $0 + 12 }))
        #expect(!EarDrill.gradePlayBack(question, heard: Array(question.pitches.dropLast())))
        #expect(EarDrill.grade(question, chosen: 0) == .correct)
    }

    @Test func pluckSynthRendersATone() {
        let synth = PluckSynth(sampleRate: 48_000)
        let samples = synth.render(PluckSynth.sequence([57, 64], a4: 440, spacing: 0.5), duration: 1.2)
        #expect(samples.count == 57_600)
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.01 && samples.allSatisfy { abs($0) <= 1 })
    }

    @Test func routineAddsAnEarBlockOnLongDays() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 30, dueFretCards: 0, learnedFretCards: 30))
        #expect(routine.map(\.kind) == [.tuner, .chordChange, .scale, .rhythm, .ear, .free])
        #expect(RoutineBuilder.totalMinutes(routine) == 30)
    }
}
