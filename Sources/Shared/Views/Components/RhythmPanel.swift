import SwiftUI
import SwCharts

/// Rhythm at rest: subdivision, BPM, bars, Start. Running: beat dots, a timing needle for the last strike and
/// the running count. Finished: on-time share, rushing/dragging, the spread as a bell curve.
/// Identical on both platforms.
struct RhythmHomePanel: View {
    @Binding var subdivisionRaw: Int
    @Binding var bpm: Int
    @Binding var bars: Int
    var best: Double?
    var onStart: () -> Void

    private var subdivision: RhythmJudge.Subdivision { RhythmJudge.Subdivision(rawValue: subdivisionRaw) ?? .quarters }

    var body: some View {
        VStack(spacing: 18) {
            Picker("Subdivision", selection: $subdivisionRaw) {
                ForEach(RhythmJudge.Subdivision.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Stepper("\(bpm) BPM", value: $bpm, in: Int(ClickSchedule.bpmRange.lowerBound)...Int(ClickSchedule.bpmRange.upperBound), step: 5)
                .font(.title3.monospacedDigit())
            Stepper("\(bars) bars", value: $bars, in: 2...16, step: 2).font(.title3.monospacedDigit())
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "metronome").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("Strum or pick \(subdivision.title.lowercased()) on the click. One bar counts you in.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if let best { Text("Best spread \(Int(best.rounded())) ms").font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Button {
                onStart()
            } label: {
                Label("Start · \(bpm) BPM", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

struct RhythmDrillPanel: View {
    @Bindable var model: RhythmDrillViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
            switch model.phase {
            case .finished(let summary):
                finished(summary)
            default:
                running
            }
        }
        .padding()
        .onAppear { if model.phase == .ready { model.start() } }
        .onDisappear { model.stop() }
    }

    private var running: some View {
        VStack(spacing: 18) {
            Text(model.title).font(.title2.bold())
            beatDots
            if model.phase == .countingIn {
                Text("Count-in…").font(.headline).foregroundStyle(.orange)
            } else {
                Text("\(model.summary.onTime) on time · \(model.strikes.count - model.summary.onTime) off").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
            needle
            Spacer()
            LevelMeter(level: model.audio.level).padding(.horizontal, 40)
            micStatus
            Button("Stop") { model.stop(); onDone() }.font(.footnote)
        }
    }

    private var beatDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<model.beatsPerBar, id: \.self) { index in
                let isOn = model.phase != .ready && model.beatInBar == index
                Circle()
                    .fill(isOn ? (index == 0 ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.2))
                    .frame(width: index == 0 ? 30 : 24, height: index == 0 ? 30 : 24)
                    .animation(.linear(duration: 0.05), value: isOn)
            }
        }
        .frame(height: 34)
    }

    /// Early to the left, late to the right, ±150 ms across the width.
    private var needle: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let offset = model.lastOffset ?? 0
            let x = width / 2 + CGFloat(max(-150, min(150, offset))) / 150 * width / 2
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 10)
                Capsule().fill(Color.green.opacity(0.35)).frame(width: width * CGFloat(RhythmJudge.onTimeWindow / 150), height: 10)
                    .offset(x: width / 2 - width * CGFloat(RhythmJudge.onTimeWindow / 150) / 2)
                Rectangle().fill(.secondary).frame(width: 1, height: 22).offset(x: width / 2)
                if model.lastOffset != nil {
                    Circle().fill(abs(offset) <= RhythmJudge.onTimeWindow ? Color.green : Color.red).frame(width: 18, height: 18)
                        .offset(x: x - 9)
                        .animation(.easeOut(duration: 0.08), value: offset)
                }
            }
            .frame(height: 24)
        }
        .frame(height: 24)
        .overlay(alignment: .bottom) {
            HStack { Text("early").font(.caption2); Spacer(); Text("late").font(.caption2) }.foregroundStyle(.secondary).offset(y: 16)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var micStatus: some View {
        switch model.audio.status {
        case .denied:
            HStack {
                Text("Microphone is off.")
                if let url = model.audio.privacySettingsURL { Link("Settings", destination: url) }
            }
            .font(.footnote)
        case .unavailable(let reason):
            HStack { Text(reason); Button("Retry") { model.audio.retry() } }.font(.footnote)
        default:
            EmptyView()
        }
    }

    private func finished(_ summary: RhythmJudge.Summary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: summary.accuracy >= 0.75 ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 56)).foregroundStyle(summary.accuracy >= 0.75 ? .green : .orange)
            Text("\(Int((summary.accuracy * 100).rounded()))% on time").font(.title.bold())
            Text(summary.tendency).font(.headline).foregroundStyle(abs(summary.meanOffset) < 10 ? .green : .orange)
            Text("\(summary.strikes) strikes · \(summary.missed) missed · spread ±\(Int(summary.standardDeviation.rounded())) ms")
                .font(.footnote).foregroundStyle(.secondary)
            if let best = model.best { Text("Best spread \(Int(best.rounded())) ms").font(.footnote).foregroundStyle(.secondary) }
            if summary.strikes >= 2, summary.standardDeviation > 0 {
                Form {
                    NormalDistributionChart(mean: summary.meanOffset, stddev: summary.standardDeviation, count: summary.strikes, title: "Timing, ms (early < 0 < late)")
                }
                .formStyle(.grouped)
                .frame(height: 200)
            }
            HStack(spacing: 16) {
                Button("Again") { model.reset(); model.start() }.buttonStyle(.bordered).controlSize(.large)
                Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer()
        }
    }
}
