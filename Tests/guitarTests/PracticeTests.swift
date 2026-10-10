import Foundation
import Testing
import SwiftData
@testable import guitar

struct AutoGradeTests {
    @Test func wrongIsOneRightGetsBetterWithSpeed() {
        #expect(AutoGrade.quality(correct: false, response: 0.5) == 1)
        #expect(AutoGrade.quality(correct: true, response: 1) == 5)
        #expect(AutoGrade.quality(correct: true, response: 3) == 4)
        #expect(AutoGrade.quality(correct: true, response: 8) == 3)
    }

    @Test func rollingMeanMovesTowardsNewAnswers() {
        let mean = AutoGrade.updatedMean(4, with: 2, count: 2)
        #expect(mean == 3)
        #expect(AutoGrade.updatedMean(4, with: 2, count: 100) == 3.8)  // capped at 1/10 weight
    }
}

struct CardMergeTests {
    @Test func keepsTheMostProgress() {
        let a = CardMerge.Snapshot(attempts: 4, correct: 3, meanResponse: 2, srInterval: 6, srEasinessFactor: 2.6, srRepetitions: 2, srDueDate: Date(timeIntervalSince1970: 200))
        let b = CardMerge.Snapshot(attempts: 2, correct: 1, meanResponse: 5, best: 30, srInterval: 1, srEasinessFactor: 2.5, srRepetitions: 1, srDueDate: Date(timeIntervalSince1970: 100))
        let merged = CardMerge.merge([a, b])
        #expect(merged.attempts == 6 && merged.correct == 4)
        #expect(merged.meanResponse == 3)
        #expect(merged.best == 30)
        #expect(merged.srRepetitions == 2 && merged.srInterval == 6 && merged.srEasinessFactor == 2.6)
        #expect(merged.srDueDate == Date(timeIntervalSince1970: 100))
    }
}

struct FretboardDrillTests {
    let board = Fretboard()

    @Test func cardKeysRoundTripAndIncludeTheTuning() {
        let key = FretboardDrill.cardKey(position: FretPosition(string: 3, fret: 7), tuning: .standard)
        #expect(key == "fret:E2 A2 D3 G3 B3 E4:s3f7")
        #expect(FretboardDrill.position(fromCardKey: key) == FretPosition(string: 3, fret: 7))
        #expect(FretboardDrill.cardKey(position: FretPosition(string: 6, fret: 0), tuning: .dropD) != FretboardDrill.cardKey(position: FretPosition(string: 6, fret: 0), tuning: .standard))
    }

    @Test func dueCardsComeFirstThenUnseenPositions() {
        let due = [FretboardDrill.cardKey(position: FretPosition(string: 2, fret: 5), tuning: .standard)]
        let seen = Set(due + [FretboardDrill.cardKey(position: FretPosition(string: 1, fret: 0), tuning: .standard)])
        let queue = FretboardDrill.queue(fretboard: board, scope: .default, dueKeys: due, seenKeys: seen, count: 5, seed: 1)
        #expect(queue.first?.position == FretPosition(string: 2, fret: 5))
        #expect(queue.count == 5)
        #expect(!queue.dropFirst().contains { $0.position == FretPosition(string: 1, fret: 0) })  // seen, not due: last
        #expect(queue.allSatisfy { [0, 2, 4, 5, 7, 9, 11].contains($0.pitchClass) })  // naturals only by default
    }

    @Test func queueIsRepeatableForASeed() {
        let a = FretboardDrill.queue(fretboard: board, scope: .default, dueKeys: [], seenKeys: [], seed: 42)
        let b = FretboardDrill.queue(fretboard: board, scope: .default, dueKeys: [], seenKeys: [], seed: 42)
        #expect(a == b)
    }

    @Test func dueCardsOutsideTheScopeAreLeftOut() {
        let due = [FretboardDrill.cardKey(position: FretPosition(string: 1, fret: 15), tuning: .standard)]
        let queue = FretboardDrill.queue(fretboard: board, scope: .default, dueKeys: due, seenKeys: Set(due), count: 3, seed: 1)
        #expect(!queue.contains { $0.position.fret == 15 })
    }

    @Test func micJudgingTrustsTheStringAndFollowsTheReferenceA() {
        let prompt = FretboardDrill.Prompt(position: FretPosition(string: 3, fret: 9), pitch: 64)  // E4 on the G string
        #expect(FretboardDrill.judge(prompt: prompt, heardFrequency: 329.63, referenceA: 440) == .correct)
        #expect(FretboardDrill.judge(prompt: prompt, heardFrequency: 329.63 * 432 / 440, referenceA: 432) == .correct)
        #expect(FretboardDrill.judge(prompt: prompt, heardFrequency: 349.23, referenceA: 440) == .wrong(heardPitch: 65))  // F4
        #expect(FretboardDrill.judge(prompt: prompt, heardFrequency: 164.8, referenceA: 440) == .wrong(heardPitch: 52))   // octave below isn't it
        #expect(FretboardDrill.judge(prompt: prompt, heardFrequency: 338, referenceA: 440) == .wrong(heardPitch: nil))   // 43 cents sharp: in between
    }

    @Test func tapJudgingComparesPitchClasses() {
        let prompt = FretboardDrill.Prompt(position: FretPosition(string: 5, fret: 3), pitch: 48)  // C3
        #expect(FretboardDrill.judge(prompt: prompt, tappedPitchClass: 0) == .correct)
        #expect(FretboardDrill.judge(prompt: prompt, tappedPitchClass: 1) == .wrong(heardPitch: 1))
    }

    @Test func showsWhereAWrongNoteLivesOnTheAskedString() {
        #expect(FretboardDrill.heardPosition(pitch: 65, onString: 3, fretboard: board) == FretPosition(string: 3, fret: 10))
        #expect(FretboardDrill.heardPosition(pitch: 30, onString: 3, fretboard: board) == nil)
    }
}

struct MasteryMapTests {
    @Test func masteryGrowsWithAccuracyAndSchedule() {
        #expect(MasteryMap.mastery(.init(accuracy: 1, repetitions: 0, isDue: false)) == 0.4)
        #expect(MasteryMap.mastery(.init(accuracy: 1, repetitions: 5, isDue: false)) == 1)
        #expect(MasteryMap.mastery(.init(accuracy: 0.5, repetitions: 5, isDue: false)) == 0.5)
    }
}

@MainActor
struct CardStoreTests {
    /// The container must outlive the store: a ModelContext doesn't keep its container alive.
    private func makeStore() throws -> (ModelContainer, CardStore) {
        let container = try ModelContainer(
            for: SkillCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return (container, CardStore(context: container.mainContext))
    }

    @Test func cardsAreCreatedLazilyAndReused() throws {
        let (container, store) = try makeStore()
        defer { _ = container }
        #expect(store.all(kind: .fretPosition).isEmpty)
        let first = store.card(kind: .fretPosition, key: "fret:x:s1f0")
        let again = store.card(kind: .fretPosition, key: "fret:x:s1f0")
        #expect(first === again)
        #expect(store.all(kind: .fretPosition).count == 1)
    }

    @Test func recordingGradesAndReschedules() throws {
        let (container, store) = try makeStore()
        defer { _ = container }
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.record(kind: .fretPosition, key: "k", correct: true, response: 1, thresholds: .fretPosition, now: now)
        let card = store.card(kind: .fretPosition, key: "k")
        #expect(card.attempts == 1 && card.correct == 1)
        #expect(card.srRepetitions == 1)
        #expect(card.srDueDate > now)
        #expect(store.dueKeys(kind: .fretPosition, now: now).isEmpty)
        store.record(kind: .fretPosition, key: "k", correct: false, response: 3, thresholds: .fretPosition, now: now)
        #expect(store.card(kind: .fretPosition, key: "k").srRepetitions == 0)
    }

    @Test func dedupeMergesSameKeyCards() throws {
        let (container, store) = try makeStore()
        defer { _ = container }
        let a = SkillCard(kind: "fretPosition", key: "k")
        let b = SkillCard(kind: "fretPosition", key: "k")
        let other = SkillCard(kind: "fretPosition", key: "other")
        store.context.insert(a); store.context.insert(b); store.context.insert(other)
        a.attempts = 3; a.correct = 2; a.srRepetitions = 2; a.srInterval = 6
        b.attempts = 1; b.correct = 1; b.srDueDate = .distantPast
        try store.context.save()
        #expect(store.dedupe() == 1)
        let cards = store.all(kind: .fretPosition)
        #expect(cards.count == 2)
        let merged = try #require(cards.first { $0.key == "k" })
        #expect(merged.attempts == 4 && merged.correct == 3 && merged.srRepetitions == 2 && merged.srDueDate == .distantPast)
        #expect(store.dedupe() == 0)
    }
}
