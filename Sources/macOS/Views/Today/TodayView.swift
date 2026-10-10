import SwiftUI
import SwiftData

/// Today tab: goal ring, start/resume, routine preview; the running session takes over the screen.
struct TodayView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query(filter: #Predicate<SkillCard> { $0.kind == "fretPosition" }) private var cards: [SkillCard]
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 20
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.drillScope) private var scopeData = Data()
    @State private var runner: SessionRunnerViewModel?
    @State private var skipped: Set<String> = []

    private var fretboard: Fretboard { Fretboard(tuning: Tuning.named(description: tuningText) ?? .standard) }
    private var scope: FretboardDrill.Scope { (try? JSONDecoder().decode(FretboardDrill.Scope.self, from: scopeData)) ?? .default }
    private var pairs: [(startedAt: Date, duration: TimeInterval)] { sessions.map { ($0.startedAt, $0.duration) } }
    private var minutesToday: Double { PracticeStats.minutes(on: .now, sessions: pairs) }
    private var resumable: PracticeSession? {
        sessions.first { !$0.isComplete && PracticeStats.calendar.isDateInToday($0.startedAt) }
    }
    private var routine: [RoutineItem] {
        let now = Date.now
        let inputs = RoutineBuilder.Inputs(
            goalMinutes: goalMinutes,
            dueFretCards: cards.filter { $0.srDueDate <= now }.count,
            learnedFretCards: cards.count,
            minutesDoneToday: Int(minutesToday)
        )
        return RoutineBuilder.routine(inputs).filter { !skipped.contains($0.id) }
    }

    var body: some View {
        Group {
            if let runner {
                SessionPanel(runner: runner, audio: audio, fretboard: fretboard, leftHanded: leftHanded, preferSharps: preferSharps, scope: scope) {
                    self.runner = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End") { runner.endEarly() }.disabled(runner.isFinished)
                    }
                }
            } else {
                TodayPanel(
                    minutesToday: minutesToday, goalMinutes: goalMinutes,
                    streak: PracticeStats.streak(sessions: pairs),
                    routine: routine, canResume: resumable != nil,
                    onStart: start,
                    onSkip: { skipped.insert($0.id) }
                )
            }
        }
        .frame(maxWidth: 480)
        .navigationTitle("Today")
    }

    private func start() {
        runner = SessionRunnerViewModel(routine: routine, goalMinutes: goalMinutes, context: context, resuming: resumable)
    }
}
