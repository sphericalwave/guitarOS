import SwiftUI
import MusicTheoryKit

/// Theory flashcards at rest: kind picker and Start. Identical on both platforms.
struct TheoryHomePanel: View {
    @Binding var kindRaw: String
    var dueCount: Int
    var onStart: () -> Void

    private var kind: TheoryDrill.Kind { TheoryDrill.Kind(rawValue: kindRaw) ?? .intervalNote }

    var body: some View {
        VStack(spacing: 18) {
            Picker("Kind", selection: $kindRaw) {
                ForEach(TheoryDrill.Kind.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed").font(.system(size: 56)).foregroundStyle(.secondary)
                Text(description).multilineTextAlignment(.center).foregroundStyle(.secondary)
                if dueCount > 0 { Text("\(dueCount) due").font(.footnote).foregroundStyle(.orange) }
            }
            Spacer()
            Button {
                onStart()
            } label: {
                Label("Start · \(TheoryDrill.questionsPerRound) cards", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var description: String {
        switch kind {
        case .intervalNote: "\"The major 3rd above D?\" Tap the note. Silent: no guitar needed."
        case .scaleNote: "\"Which note is not in A Dorian?\" Four notes, one outsider."
        case .keyChord: "\"The IV chord of G major?\" Diatonic triads in major and minor keys."
        case .degree: "\"Which degree is F♯ in D major?\" Answer 1–7."
        }
    }
}

struct TheoryDrillPanel: View {
    @Bindable var model: TheoryDrillViewModel
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
                Text(question.prompt).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text("\(model.position + 1) of \(model.questions.count)").font(.footnote).foregroundStyle(.secondary)
                feedback(question)
            }
            .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private func feedback(_ question: TheoryDrill.Question) -> some View {
        if case .answered(let verdict) = model.phase {
            switch verdict {
            case .correct:
                Label("Yes", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3.bold())
            case .wrong:
                let right = question.answerPitchClass.map { PitchName.name(forPitchClass: $0, preferSharps: model.preferSharps) } ?? question.choices[question.answer]
                Label("It's \(right)", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.title3.bold())
            }
        } else {
            Text(" ").font(.title3)
        }
    }

    @ViewBuilder
    private var answers: some View {
        if let question = model.current {
            if question.answerPitchClass != nil {
                NoteNameGrid(preferSharps: model.preferSharps, isEnabled: model.phase == .asking) { model.answer($0) }
            } else {
                let columns = question.choices.count > 4 ? 4 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(question.choices.indices, id: \.self) { index in
                        Button {
                            model.answer(index)
                        } label: {
                            Text(question.choices[index]).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint(for: index, question: question))
                        .disabled(model.phase != .asking)
                    }
                }
            }
        }
    }

    private func tint(for index: Int, question: TheoryDrill.Question) -> Color? {
        guard case .answered(let verdict) = model.phase else { return nil }
        if index == question.answer { return .green }
        if case .wrong(let chosen) = verdict, chosen == index { return .red }
        return nil
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
