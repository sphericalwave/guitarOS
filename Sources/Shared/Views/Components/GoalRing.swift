import SwiftUI

/// Minutes today against the daily goal.
struct GoalRing: View {
    var minutes: Double
    var goalMinutes: Int

    private var fraction: Double { min(1, minutes / Double(max(goalMinutes, 1))) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(fraction >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int(minutes.rounded()))").font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                Text("of \(goalMinutes) min").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityLabel("\(Int(minutes.rounded())) of \(goalMinutes) minutes practised today")
    }
}
