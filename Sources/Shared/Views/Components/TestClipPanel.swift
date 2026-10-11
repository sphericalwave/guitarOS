import SwiftUI

/// Record a labelled strum (chord, guitar, input) for tuning chord detection, and share the clips.
/// Identical on both platforms.
struct TestClipPanel: View {
    @Bindable var model: TestClipViewModel
    var tuning: Tuning
    @AppStorage(SettingsKey.testClipGuitar) private var lastGuitar = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Picker("Chord", selection: $model.chord) {
                    ForEach(ChordLibrary.voicings) { Text($0.name).tag($0) }
                }
                TextField("Guitar", text: $model.guitar, prompt: Text(lastGuitar.isEmpty ? "Strat, Taylor acoustic…" : lastGuitar))
                    .onSubmit { commitGuitar() }
                LabeledContent("Input", value: model.audio.inputProfile.title)
            } header: {
                Text("What you'll play")
            } footer: {
                Text("Strum the chord once, cleanly, as you would in the drill. The clip is what the app heard, with its label, so detection can be tuned on your guitar.")
            }
            Section {
                VStack(spacing: 12) {
                    LevelMeter(level: model.audio.level)
                    status
                    recordButton
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            if !model.clips.isEmpty {
                Section {
                    ForEach(model.clips) { clip in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(clip.chord) · \(clip.guitar.isEmpty ? "guitar" : clip.guitar)").font(.headline)
                                Text("\(InputProfile(rawValue: clip.input)?.title ?? clip.input) · \(clip.duration.formatted(.number.precision(.fractionLength(1)))) s · \(clip.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(items: [model.audioURL(for: clip), model.metadataURL(for: clip)]) { Image(systemName: "square.and.arrow.up") }
                                .labelStyle(.iconOnly)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { model.delete(clip) } }
                        .contextMenu { Button("Delete", role: .destructive) { model.delete(clip) } }
                    }
                } header: {
                    HStack {
                        Text("\(model.clips.count) clips")
                        Spacer()
                        ShareLink("Share all", items: model.allURLs).font(.footnote)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.appear() }
        .onDisappear { commitGuitar(); model.disappear() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            switch model.audio.status {
            case .listening: Text("Listening").font(.footnote).foregroundStyle(.secondary)
            case .denied:
                VStack(spacing: 4) {
                    Text("Microphone access is off.").font(.footnote).foregroundStyle(.secondary)
                    if let url = model.audio.privacySettingsURL { Button("Open Settings") { openURL(url) }.font(.footnote) }
                }
            case .unavailable(let reason): Text(reason).font(.footnote).foregroundStyle(.secondary)
            default: Text("Starting the microphone…").font(.footnote).foregroundStyle(.secondary)
            }
        case .recording:
            Text("Recording \(model.elapsed.formatted(.number.precision(.fractionLength(1)))) s — strum now")
                .font(.footnote).foregroundStyle(.red).monospacedDigit()
        case .saved(let clip):
            Label("Saved \(clip.chord) · \(clip.duration.formatted(.number.precision(.fractionLength(1)))) s", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        case .failed(let reason):
            Text(reason).font(.footnote).foregroundStyle(.orange)
        }
    }

    private var recordButton: some View {
        Group {
            if model.phase == .recording {
                Button { model.stopRecording() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    commitGuitar()
                    if model.guitar.isEmpty { model.guitar = lastGuitar }
                    model.startRecording(tuning: tuning)
                } label: {
                    Label("Record \(model.chord.name)", systemImage: "record.circle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isListening)
            }
        }
        .controlSize(.large)
    }

    /// The last guitar name is the placeholder next time; an empty field means "the same guitar".
    private func commitGuitar() {
        let typed = model.guitar.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { lastGuitar = typed }
    }
}
