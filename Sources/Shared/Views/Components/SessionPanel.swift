import SwiftUI

/// The running session: block header with progress, then the block's own panel (tuner, drill, timer),
/// then the end screen. Identical on both platforms.
struct SessionPanel: View {
    @Bindable var runner: SessionRunnerViewModel
    let audio: AudioHub
    var fretboard: Fretboard
    var leftHanded: Bool
    var preferSharps: Bool
    var scope: FretboardDrill.Scope
    var onDone: () -> Void

    @State private var tuner: TunerViewModel?
    @State private var drill: FretboardDrillViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if let summary = runner.summary {
                SessionSummaryPanel(summary: summary, onDone: onDone)
            } else if let item = runner.current {
                header(item)
                block(item)
            }
        }
        .onChange(of: runner.index) { tuner = nil; drill = nil }
    }

    private func header(_ item: RoutineItem) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: runner.progress)
            HStack {
                Label(item.title, systemImage: item.kind.icon).font(.headline)
                Spacer()
                Text("Block \(runner.index + 1) of \(runner.routine.count) · \(max(runner.minutesLeft, 0)) min left")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding([.horizontal, .top])
    }

    @ViewBuilder
    private func block(_ item: RoutineItem) -> some View {
        switch item.kind {
        case .tuner:
            ScrollView {
                if let tuner { TunerPanel(model: tuner) }
            }
            .task { if tuner == nil { tuner = TunerViewModel(audio: audio, tuning: fretboard.tuning) } }
            Button("In tune, next") { runner.completeBlock() }
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
        case .fretboard:
            if let drill {
                DrillPanel(model: drill, leftHanded: leftHanded, preferSharps: preferSharps, scope: scope) {
                    runner.completeBlock(attempts: drill.correctCount + drill.wrongCount, correct: drill.correctCount)
                }
                .onChange(of: runner.isBlockTimeUp) { if runner.isBlockTimeUp, drill.phase != .finished { finishDrillBlock(drill) } }
            } else {
                ProgressView().task {
                    let model = FretboardDrillViewModel(
                        fretboard: fretboard,
                        mode: FretboardDrill.Mode(rawValue: item.detail ?? "") ?? .findTheNote,
                        audio: audio, cards: runner.cards
                    )
                    model.start(scope: scope, count: max(6, Int(Double(item.minutes) * 60 / RoutineBuilder.secondsPerCard)))
                    drill = model
                }
            }
        default:
            FreePracticePanel(elapsed: runner.elapsed, minutes: item.minutes) { runner.completeBlock() }
        }
    }

    private func finishDrillBlock(_ drill: FretboardDrillViewModel) {
        let attempts = drill.correctCount + drill.wrongCount
        drill.stop()
        runner.completeBlock(attempts: attempts, correct: drill.correctCount)
    }
}

/// A timed block with nothing to grade: play what you like, stop when the time's up.
struct FreePracticePanel: View {
    var elapsed: TimeInterval
    var minutes: Int
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(Duration.seconds(max(0, Double(minutes) * 60 - elapsed)).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
            Text("Play whatever you're working on. The minutes count.").foregroundStyle(.secondary)
            Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding()
    }
}

/// End of the sitting: what improved, the streak, and what's due tomorrow. Never a blank list.
struct SessionSummaryPanel: View {
    var summary: SessionRunnerViewModel.Summary
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("\(summary.minutes) minutes practised").font(.title.bold())
            if summary.cardsTotal > 0 {
                Text("\(summary.cardsRight) of \(summary.cardsTotal) notes right").font(.title3)
            }
            Label(summary.streak == 1 ? "1 day streak" : "\(summary.streak) day streak", systemImage: "flame.fill")
                .foregroundStyle(.orange).font(.headline)
            Text("Tomorrow: \(summary.dueTomorrow) notes due").foregroundStyle(.secondary)
            Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top)
            Spacer()
        }
        .padding()
    }
}
