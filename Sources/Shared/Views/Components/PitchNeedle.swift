import SwiftUI

/// A horizontal cents gauge: −50 on the left, +50 on the right, green when within the in-tune band.
struct PitchNeedle: View {
    var cents: Double?
    var isInTune: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = width / 2
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)
                // In-tune band
                Capsule().fill(isInTune ? Color.green.opacity(0.5) : Color.secondary.opacity(0.25))
                    .frame(width: width * 0.06, height: 6)
                    .offset(x: center - width * 0.03)
                // Tick marks
                ForEach([-50, -25, 0, 25, 50], id: \.self) { tick in
                    Rectangle().fill(.secondary).frame(width: tick == 0 ? 2 : 1, height: tick == 0 ? 22 : 12)
                        .offset(x: center + CGFloat(tick) / 50 * (width / 2 - 8) - (tick == 0 ? 1 : 0.5))
                }
                if let cents {
                    let clamped = min(max(cents, -50), 50)
                    Capsule().fill(isInTune ? Color.green : (cents < 0 ? Color.orange : Color.red))
                        .frame(width: 5, height: 36)
                        .offset(x: center + CGFloat(clamped) / 50 * (width / 2 - 8) - 2.5)
                        .animation(.easeOut(duration: 0.08), value: clamped)
                }
            }
            .frame(height: 36)
        }
        .frame(height: 36)
        .accessibilityLabel(cents.map { "\(Int($0.rounded())) cents" } ?? "No pitch")
    }
}

/// Input level, 0...1.
struct LevelMeter: View {
    var level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(level > 0.85 ? Color.red : Color.accentColor)
                    .frame(width: max(0, proxy.size.width * level))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Input level")
    }
}
