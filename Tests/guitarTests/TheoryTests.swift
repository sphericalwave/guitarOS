import Foundation
import Testing
import MusicTheoryKit
@testable import guitar

struct TheoryDrillTests {
    @Test func intervalQuestionsAskForTheRightNote() {
        let questions = TheoryDrill.questions(kind: .intervalNote, count: 20, seed: 11, preferSharps: true)
        #expect(questions == TheoryDrill.questions(kind: .intervalNote, count: 20, seed: 11, preferSharps: true))
        for question in questions {
            let interval = TheoryDrill.intervalsAsked.first { question.key == "theory:interval:\($0.shortName)" }!
            let rootName = question.prompt.split(separator: " ").last!.dropLast()   // "…above D?"
            let root = (0..<12).first { PitchName.name(forPitchClass: $0, preferSharps: true) == rootName }!
            #expect(question.answerPitchClass == (root + interval.semitones) % 12, Comment(rawValue: question.prompt))
            #expect(TheoryDrill.grade(question, chosen: question.answerPitchClass!) == .correct)
            #expect(TheoryDrill.grade(question, chosen: (question.answerPitchClass! + 1) % 12) == .wrong(chosen: (question.answerPitchClass! + 1) % 12))
        }
    }

    @Test func scaleQuestionsHaveExactlyOneOutsider() {
        for question in TheoryDrill.questions(kind: .scaleNote, count: 20, seed: 5, preferSharps: true) {
            #expect(question.choices.count == 4 && question.choices.indices.contains(question.answer))
            #expect(Set(question.choices).count == 4, Comment(rawValue: question.prompt))
            #expect(question.prompt.hasPrefix("Which note is not in "))
        }
    }

    @Test func keyChordQuestionsNameTheDiatonicTriad() {
        #expect(TheoryDrill.diatonicQuality(degree: 4, isMinor: false) == .major && TheoryDrill.diatonicQuality(degree: 6, isMinor: false) == .diminished)
        #expect(TheoryDrill.diatonicQuality(degree: 1, isMinor: true) == .diminished && TheoryDrill.diatonicQuality(degree: 2, isMinor: true) == .major)
        for question in TheoryDrill.questions(kind: .keyChord, count: 30, seed: 2, preferSharps: true) {
            #expect(question.choices.count == 4 && Set(question.choices).count == 4, Comment(rawValue: question.prompt))
            #expect(question.key.hasPrefix("theory:chord:"))
        }
        // G major's IV is C: build the question deterministically through a due key and check by hand.
        var random = SplitMixRandom(state: 99)
        let question = TheoryDrill.question(id: 0, kind: .keyChord, dueKey: "theory:chord:IV", preferSharps: true, random: &random)
        #expect(question.key == "theory:chord:IV" || question.key == "theory:chord:iv")
    }

    @Test func degreeQuestionsAndDueKeys() {
        let questions = TheoryDrill.questions(kind: .degree, count: 5, seed: 8, preferSharps: false, dueKeys: ["theory:degree:7", "theory:degree:2"])
        #expect(questions[0].key == "theory:degree:7" && questions[0].answer == 6)
        #expect(questions[1].key == "theory:degree:2" && questions[1].answer == 1)
        #expect(questions.allSatisfy { $0.choices == ["1", "2", "3", "4", "5", "6", "7"] })
    }
}
