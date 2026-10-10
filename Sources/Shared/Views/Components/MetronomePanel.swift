import SwiftUI

/// Metronome controls: big BPM with the last-value placeholder, ± and tap tempo, start/stop, beats per bar
/// behind a disclosure. Identical on both platforms.
struct MetronomePanel: View {
    @Bindable var model: MetronomeViewModel
    @AppStorage(SettingsKey.lastBPM) private var lastBPM = 100
    @State private var bpmText = ""
    @State private var showAccent = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            beatDots
            HStack {
                TextField("\(lastBPM)", text: $bpmText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { if !focused { commit() } }
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(width: 160)
                Text("BPM").font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button { adjust(-5) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.buttonStyle(.bordered)
                Button("Tap tempo") { model.tap() }.buttonStyle(.bordered).controlSize(.large)
                Button { adjust(5) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.buttonStyle(.bordered)
            }
            Button {
                model.toggle()
            } label: {
                Label(model.isRunning ? "Stop" : "Start", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isRunning ? .red : .accentColor)
            DisclosureGroup("Accent", isExpanded: $showAccent) {
                Picker("Beats per bar", selection: $model.beatsPerBar) {
                    ForEach([2, 3, 4, 6], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .onChange(of: model.bpm) { lastBPM = Int(model.bpm) }
        .onDisappear { model.stop() }
    }

    private var beatDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<model.beatsPerBar, id: \.self) { index in
                let isOn = model.isRunning && model.beat.map { $0.index % model.beatsPerBar == index } == true
                Circle()
                    .fill(isOn ? (index == 0 ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.2))
                    .frame(width: index == 0 ? 26 : 20, height: index == 0 ? 26 : 20)
                    .animation(.linear(duration: 0.05), value: isOn)
            }
        }
        .frame(height: 30)
    }

    /// Empty means keep the last BPM; the placeholder shows it.
    private func commit() {
        if let value = Double(bpmText.trimmingCharacters(in: .whitespaces)) { model.bpm = value }
        bpmText = ""
    }

    private func adjust(_ delta: Double) { model.bpm += delta }
}
