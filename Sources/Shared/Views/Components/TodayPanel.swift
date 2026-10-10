import SwiftUI

/// Today at rest: the goal ring, one Start (or Resume) button, and the routine preview.
struct TodayPanel: View {
    var minutesToday: Double
    var goalMinutes: Int
    var streak: Int
    var routine: [RoutineItem]
    var canResume: Bool
    var onStart: () -> Void
    var onSkip: (RoutineItem) -> Void

    var body: some View {
        VStack(spacing: 20) {
            GoalRing(minutes: minutesToday, goalMinutes: goalMinutes)
            if streak > 0 {
                Label(streak == 1 ? "1 day streak" : "\(streak) day streak", systemImage: "flame.fill")
                    .foregroundStyle(.orange).font(.subheadline.weight(.semibold))
            }
            Button {
                onStart()
            } label: {
                Label(canResume ? "Resume today's practice" : "Start today's practice (\(RoutineBuilder.totalMinutes(routine)) min)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            VStack(spacing: 0) {
                ForEach(routine) { item in
                    HStack {
                        Label(item.title, systemImage: item.kind.icon)
                        Spacer()
                        Text("\(item.minutes) min").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .contextMenu { Button("Skip today", systemImage: "forward") { onSkip(item) } }
                    if item.id != routine.last?.id { Divider() }
                }
            }
            .padding(.horizontal)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
        .padding()
    }
}
