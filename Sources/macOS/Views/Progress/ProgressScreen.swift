import SwiftUI
import SwiftData
import SwCharts

/// Progress tab: calendar heatmap, D/W/M practice minutes against the daily goal, totals.
struct ProgressScreen: View {
    @Query(sort: \PracticeSession.startedAt) private var sessions: [PracticeSession]
    @Query(filter: #Predicate<SkillCard> { $0.kind == "fretPosition" }) private var cards: [SkillCard]
    @AppStorage(SettingsKey.progressChartPeriod) private var period: ChartPeriod = .week
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 20

    private var pairs: [(startedAt: Date, duration: TimeInterval)] { sessions.map { ($0.startedAt, $0.duration) } }
    private var daily: [Date: Double] { PracticeStats.dailyMinutes(sessions: pairs) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 24) {
                    stat("\(PracticeStats.streak(sessions: pairs))", "day streak")
                    stat("\(Int(pairs.reduce(0) { $0 + $1.duration } / 60))", "minutes total")
                    stat("\(cards.filter { $0.srRepetitions >= 2 }.count)", "notes known")
                }
                .frame(maxWidth: .infinity)
            }
            Section("Practice days") {
                CalendarHeatmap(weeks: 20) { day in
                    PracticeStats.intensity(minutes: daily[PracticeStats.calendar.startOfDay(for: day)] ?? 0, goalMinutes: goalMinutes)
                }
            }
            Section {
                PeriodChartView(
                    title: "Practice minutes",
                    samples: PracticeStats.minuteSamples(sessions: pairs),
                    period: period,
                    aggregation: .sum,
                    style: .bar,
                    valueLabel: { "\(Int($0)) min" },
                    goal: PeriodGoal(Double(goalMinutes))
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Progress")
        .toolbar {
            ToolbarItem(placement: .principal) { PeriodPicker(selection: $period) }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
