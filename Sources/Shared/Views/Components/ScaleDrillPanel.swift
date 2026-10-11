import SwiftUI
import MusicTheoryKit

/// The scale drill's screen body: the box with the next note lit, what's been played, the mic readout
/// or the beat, and the result. Identical on both platforms.
struct ScaleDrillPanel: View {
    @Bindable var model: ScaleDrillViewModel
    var fretboard: Fretboard
    var leftHanded: Bool
    var preferSharps: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
            switch model.phase {
            case .finished(let result):
                finished(result)
            default:
                header
                FretboardView(fretboard: fretboard, fretRange: ScaleHomePanel.visibleFrets(model.position, fretboard: fretboard), leftHanded: leftHanded, dots: dots)
                    .frame(maxHeight: .infinity)
                readout
            }
        }
        .padding()
        .onAppear { if model.phase == .ready { model.start() } }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(model.position.scale.name(preferSharps: preferSharps)).font(.title2.bold())
            Text(model.position.title + (model.mode == .timed ? " · \(Int(model.bpm)) BPM" : "")).font(.callout).foregroundStyle(.secondary)
            if model.phase == .countingIn {
                Text("Count-in…").font(.headline).foregroundStyle(.orange)
            } else {
                Text("\(min(model.index + 1, model.sequence.count)) of \(model.sequence.count)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(height: 90)
    }

    /// The box in grey, played notes green or red, the next note in the accent colour, a stray note red.
    private var dots: [FretPosition: FretboardView.Dot] {
        var dots = ScaleHomePanel.dots(model.position, preferSharps: preferSharps)
        for (step, place) in model.sequence.enumerated() {
            if let hit = model.results[step] { dots[place] = .init(color: hit ? .green : .red, label: dots[place]?.label) }
        }
        if let next = model.nextPosition {
            dots[next] = .init(color: .accentColor, label: dots[next]?.label)
        }
        if let wrong = model.wrongPosition {
            dots[wrong] = .init(color: .red, label: "✕")
        }
        return dots
    }

    private var readout: some View {
        VStack(spacing: 6) {
            LevelMeter(level: model.audio.level).padding(.horizontal, 40)
            HStack(spacing: 16) {
                Text(model.heardNote.map { "Hearing \(PitchName.name(for: UInt8(clamping: $0)))" } ?? "Listening…")
                if model.mode == .timed {
                    Text("\(model.hits) hit · \(model.missed) missed").foregroundStyle(.secondary)
                } else if model.extras > 0 {
                    Text("\(model.extras) stray").foregroundStyle(.secondary)
                }
            }
            .font(.callout.monospacedDigit())
            micStatus
        }
        .frame(minHeight: 70)
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

    private func finished(_ result: ScaleDrill.Result) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: result.isClean ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 64)).foregroundStyle(result.isClean ? .green : .orange)
            Text("\(Int((result.accuracy * 100).rounded()))% clean").font(.title.bold())
            Text("\(result.hits) of \(result.notes) notes" + (result.extras > 0 ? " · \(result.extras) stray" : "")).foregroundStyle(.secondary)
            if result.mode == .timed {
                if result.isClean {
                    Label("Clean at \(Int(result.bpm)) BPM — next time \(Int(ScaleDrill.nextBPM(after: result)))", systemImage: "hare.fill").foregroundStyle(.green).font(.headline)
                } else {
                    Text("Stay at \(Int(result.bpm)) BPM until it's clean").foregroundStyle(.secondary)
                }
                if let best = model.best { Text("Best \(Int(best)) BPM").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text(Duration.seconds(result.seconds).formatted(.time(pattern: .minuteSecond))).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button("Again") { model.reset(); model.start() }.buttonStyle(.bordered).controlSize(.large)
                Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer()
        }
    }
}
