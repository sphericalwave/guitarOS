import SwiftUI
import MusicTheoryKit

/// The trainer's screen body, identical on both platforms: prompt, fretboard, live readout or name grid.
struct DrillPanel: View {
    @Bindable var model: FretboardDrillViewModel
    var leftHanded: Bool
    var preferSharps: Bool
    var scope: FretboardDrill.Scope
    var onDone: () -> Void

    private var stringName: String {
        guard let prompt = model.current else { return "" }
        return PitchName.name(forPitchClass: Int(model.fretboard.tuning.openPitch(string: prompt.position.string)) % 12, preferSharps: preferSharps)
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
            switch model.phase {
            case .finished:
                finished
            default:
                prompt
                FretboardView(fretboard: model.fretboard, fretRange: scope.frets, leftHanded: leftHanded, dots: dots)
                    .frame(maxHeight: .infinity)
                answerArea
            }
        }
        .padding()
    }

    @ViewBuilder
    private var prompt: some View {
        if let current = model.current {
            VStack(spacing: 4) {
                switch model.mode {
                case .findTheNote:
                    Text(PitchName.name(forPitchClass: current.pitchClass, preferSharps: preferSharps))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                    Text("\(stringName) string").font(.title3).foregroundStyle(.secondary)
                case .nameTheNote:
                    Text("Name this note").font(.title2.weight(.semibold))
                    Text("\(stringName) string, fret \(current.position.fret)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            .overlay(alignment: .bottom) { feedback }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if case .answered(let verdict) = model.phase {
            switch verdict {
            case .correct:
                Label("Yes", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3.bold())
            case .wrong(let heard):
                let heardName = heard.map { model.mode == .findTheNote ? PitchName.name(for: UInt8(clamping: $0)) : PitchName.name(forPitchClass: $0, preferSharps: preferSharps) }
                Label(heardName.map { "Heard \($0)" } ?? "Not that", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.title3.bold())
            }
        }
    }

    /// Dots: the asked position after an answer (green/red), the heard note on the asked string when wrong.
    private var dots: [FretPosition: FretboardView.Dot] {
        guard let current = model.current else { return [:] }
        var result: [FretPosition: FretboardView.Dot] = [:]
        switch model.phase {
        case .asking where model.mode == .nameTheNote:
            result[current.position] = .init(color: .accentColor, label: "?")
        case .answered(.correct):
            result[current.position] = .init(color: .green, label: PitchName.name(forPitchClass: current.pitchClass, preferSharps: preferSharps))
        case .answered(.wrong(let heard)):
            result[current.position] = .init(color: .green, label: PitchName.name(forPitchClass: current.pitchClass, preferSharps: preferSharps), isHollow: true)
            if model.mode == .findTheNote, let heard,
               let where_ = FretboardDrill.heardPosition(pitch: heard, onString: current.position.string, fretboard: model.fretboard) {
                result[where_] = .init(color: .red, label: PitchName.name(forPitchClass: heard % 12, preferSharps: preferSharps))
            }
        default:
            break
        }
        return result
    }

    @ViewBuilder
    private var answerArea: some View {
        switch model.mode {
        case .findTheNote:
            VStack(spacing: 6) {
                LevelMeter(level: model.audio.level).padding(.horizontal, 40)
                Text(model.heardNote.map { "Hearing \(PitchName.name(for: UInt8(clamping: $0)))" } ?? "Listening…")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                micStatus
            }
            .frame(minHeight: 70)
        case .nameTheNote:
            NoteNameGrid(preferSharps: preferSharps, isEnabled: model.phase == .asking) { model.answer(pitchClass: $0) }
        }
    }

    @ViewBuilder
    private var micStatus: some View {
        switch model.audio.status {
        case .denied:
            HStack {
                Text("Microphone is off.")
                if let url = model.audio.privacySettingsURL { Link("Settings", destination: url) }
                Button("Use Name it instead") { model.mode = .nameTheNote }
            }
            .font(.footnote)
        case .unavailable(let reason):
            HStack { Text(reason); Button("Retry") { model.audio.retry() } }.font(.footnote)
        default:
            EmptyView()
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("\(model.correctCount) of \(model.correctCount + model.wrongCount) right").font(.title2.bold())
            Text("Cards you missed come back sooner; the rest spread out.").foregroundStyle(.secondary)
            Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
    }
}
