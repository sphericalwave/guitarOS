import Foundation
import Testing
import SwiftData
@testable import guitar

struct RoutineBuilderTests {
    @Test func startsWithTuningAndFillsToTheGoal() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 15, learnedFretCards: 30))
        #expect(routine.first?.kind == .tuner)
        #expect(routine.map(\.kind) == [.tuner, .fretboard, .free])
        #expect(RoutineBuilder.totalMinutes(routine) == 20)
        #expect(routine[1].title == "15 due notes")
        #expect(routine[1].minutes == 3)  // 15 × 12 s = 3 min
    }

    @Test func aFreshNeckGetsAnIntroductionInsteadOfDueCards() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 0, learnedFretCards: 0))
        #expect(routine[1].title == "Learn the neck")
    }

    @Test func nothingDueAndNeckKnownMeansNoFretboardBlock() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 10, dueFretCards: 0, learnedFretCards: 40))
        #expect(routine.map(\.kind) == [.tuner, .free])
    }

    @Test func resumedDayPlansOnlyTheRemainder() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 0, learnedFretCards: 40, minutesDoneToday: 15))
        #expect(RoutineBuilder.totalMinutes(routine) == 5)
    }

    @Test func manyDueCardsAreCappedToHalfTheTime() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 100, learnedFretCards: 100))
        #expect(routine[1].minutes == 9)  // half of the 19 minutes after tuning
    }
}

struct PracticeStatsTests {
    let cal = PracticeStats.calendar
    var today: Date { cal.startOfDay(for: .now) }
    func day(_ offset: Int, minutes: Double) -> (startedAt: Date, duration: TimeInterval) {
        (cal.date(byAdding: .day, value: offset, to: today)!.addingTimeInterval(3600 * 10), minutes * 60)
    }

    @Test func streakCountsConsecutiveDaysAndForgivesToday() {
        #expect(PracticeStats.streak(sessions: [day(0, minutes: 5), day(-1, minutes: 5), day(-2, minutes: 5)]) == 3)
        // Today not practised yet: yesterday's streak still stands.
        #expect(PracticeStats.streak(sessions: [day(-1, minutes: 5), day(-2, minutes: 5)]) == 2)
        // A gap breaks it.
        #expect(PracticeStats.streak(sessions: [day(0, minutes: 5), day(-2, minutes: 5)]) == 1)
        #expect(PracticeStats.streak(sessions: []) == 0)
    }

    @Test func minutesPerDaySumSessions() {
        let sessions = [day(0, minutes: 5), day(0, minutes: 7.5), day(-1, minutes: 20)]
        #expect(PracticeStats.minutes(on: .now, sessions: sessions) == 12.5)
        #expect(PracticeStats.minuteSamples(sessions: sessions).map(\.value) == [5, 7.5, 20])
    }

    @Test func heatmapIntensityIsMinutesAgainstTheGoal() {
        #expect(PracticeStats.intensity(minutes: 0, goalMinutes: 20) == 0)
        #expect(PracticeStats.intensity(minutes: 10, goalMinutes: 20) == 0.5)
        #expect(PracticeStats.intensity(minutes: 1, goalMinutes: 20) == 0.15)  // a little practice still shows
        #expect(PracticeStats.intensity(minutes: 60, goalMinutes: 20) == 1)
    }
}

@MainActor
struct SessionRunnerTests {
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: SkillCard.self, PracticeSession.self, PracticeBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return (container, container.mainContext)
    }

    @Test func savesTheSessionAtStartAndEachBlockAsItFinishes() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let routine = RoutineBuilder.routine(.init(goalMinutes: 10, dueFretCards: 5, learnedFretCards: 5))
        let runner = SessionRunnerViewModel(routine: routine, goalMinutes: 10, context: context)
        #expect(try context.fetch(FetchDescriptor<PracticeSession>()).count == 1)
        #expect(runner.current?.kind == .tuner)

        runner.completeBlock()
        #expect(try context.fetch(FetchDescriptor<PracticeBlock>()).count == 1)
        #expect(runner.current?.kind == .fretboard)
        #expect(!runner.session.isComplete)

        runner.completeBlock(attempts: 5, correct: 4)
        runner.completeBlock()
        #expect(runner.isFinished)
        #expect(runner.session.isComplete)
        #expect(runner.session.blocks?.count == 3)
        #expect(runner.summary?.cardsRight == 4 && runner.summary?.cardsTotal == 5)
        #expect(runner.summary?.minutes == 0)  // instant test blocks: under the one-minute streak threshold
        runner.stopTicking()
    }

    @Test func resumingSkipsBlocksAlreadyDoneToday() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let routine = RoutineBuilder.routine(.init(goalMinutes: 10, dueFretCards: 5, learnedFretCards: 5))
        let first = SessionRunnerViewModel(routine: routine, goalMinutes: 10, context: context)
        first.completeBlock()
        first.stopTicking()
        let unfinished = try #require(try context.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(!unfinished.isComplete)

        let resumed = SessionRunnerViewModel(routine: routine, goalMinutes: 10, context: context, resuming: unfinished)
        #expect(resumed.current?.kind == .fretboard)
        #expect(try context.fetch(FetchDescriptor<PracticeSession>()).count == 1)
        resumed.endEarly()
        #expect(unfinished.isComplete)
    }
}
