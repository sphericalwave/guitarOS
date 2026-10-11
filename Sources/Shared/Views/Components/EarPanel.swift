import SwiftUI
import MusicTheoryKit

/// Ear training at rest: mode and level, Start. Identical on both platforms.
struct EarHomePanel: View {
    @Binding var modeRaw: String
    @Binding var level: Int
    var dueCount: Int
    var onStart: () -> Void

    private var mode: EarDrill.Mode { EarDrill.Mode(rawValue: modeRaw) ?? .interval }

    var body: some View {
        VStack(spacing: 18) {
            Picker("Mode", selection: $modeRaw) {
                ForEach(EarDrill.Mode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Stepper("Level \(level)", value: $level, in: 1...4).font(.title3)
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "ear").font(.system(size: 56)).foregroundStyle(.secondary)
                Text(description).multilineTextAlignment(.center).foregroundStyle(.secondary)
                if dueCount > 0 { Text("\(dueCount) due").font(.footnote).foregroundStyle(.orange) }
            }
            Spacer()
            Button {
                onStart()
            } label: {
                Label("Start · \(EarDrill.questionsPerRound) questions", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var description: String {
        switch mode {
        case .interval: "Two notes play. Name the interval. Level \(level): \(EarDrill.intervals(level: level).map(\.shortName).joined(separator: " "))."
        case .chordQuality: "A chord plays, blocked or rolled. Name its quality. Level \(level): \(EarDrill.qualities(level: level).map(EarDrill.qualityName).joined(separator: ", "))."
        case .scaleDegree: "The tonic plays, then another note of the major key. Name the degree, 1–7."
        case .playBack: "A short pentatonic phrase plays (\(min(2 + level, 5)) notes). Play it back on the guitar; octave doesn't matter."
        }
    }
}

struct EarDrillPanel: View {
    @Bindable var model: EarDrillViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
            switch model.phase {
            case .finished:
                finished
            default:
                prompt
                Spacer()
                answers
            }
        }
        .padding()
    }

    @ViewBuilder
    private var prompt: some View {
        if let question = model.current {
            VStack(spacing: 10) {
                Text(question.mode.prompt).font(.title2.weight(.semibold))
                Text("\(model.position + 1) of \(model.questions.count)").font(.footnote).foregroundStyle(.secondary)
                Button { model.replay() } label: { Label("Play again", systemImage: "speaker.wave.2.fill").frame(minWidth: 160, minHeight: 44) }
                    .buttonStyle(.bordered)
                feedback
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if case .answered(let verdict) = model.phase, let question = model.current {
            switch verdict {
            case .correct:
                Label("Yes", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3.bold())
            case .wrong:
                let right = question.mode == .playBack ? question.pitches.map { PitchName.name(for: $0) }.joined(separator: " ") : question.choices[question.answer]
                Label("It was \(right)", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.title3.bold())
            }
        } else {
            Text(" ").font(.title3)
        }
    }

    @ViewBuilder
    private var answers: some View {
        if let question = model.current {
            if question.mode == .playBack {
                VStack(spacing: 8) {
                    LevelMeter(level: model.audio.level).padding(.horizontal, 40)
                    Text(model.heard.isEmpty ? (model.isListening ? "Listening…" : "Listen…") : model.heard.map { PitchName.name(for: $0) }.joined(separator: " "))
                        .font(.title3.monospacedDigit())
                    Text(model.heardNote.map { "Hearing \(PitchName.name(for: UInt8(clamping: $0)))" } ?? " ").font(.footnote).foregroundStyle(.secondary)
                    micStatus
                    Button("Skip") { model.skip() }.font(.footnote)
                }
                .frame(minHeight: 120)
            } else {
                let columns = question.choices.count > 7 ? 2 : 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(question.choices.indices, id: \.self) { index in
                        Button {
                            model.answer(index)
                        } label: {
                            Text(question.choices[index]).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint(for: index, question: question))
                        .disabled(model.phase != .asking)
                    }
                }
            }
        }
    }

    private func tint(for index: Int, question: EarDrill.Question) -> Color? {
        guard case .answered(let verdict) = model.phase else { return nil }
        if index == question.answer { return .green }
        if case .wrong(let chosen) = verdict, chosen == index { return .red }
        return nil
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

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("\(model.correctCount) of \(model.correctCount + model.wrongCount) right").font(.title2.bold())
            Text("What you missed comes back sooner.").foregroundStyle(.secondary)
            Button("Done") { onDone() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
    }
}
