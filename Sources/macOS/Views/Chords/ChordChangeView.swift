import SwiftUI
import SwiftData

/// One-minute chord changes, from the Practice tab's Chords page or a session block.
struct ChordChangeView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.lastBPM) private var lastBPM = 100
    @AppStorage(SettingsKey.chordPair) private var pairText = "C>G"
    @State private var model: ChordChangeViewModel?
    @State private var metronome: MetronomeViewModel?

    var body: some View {
        Group {
            if let model, let metronome {
                ChordChangePanel(model: model, leftHanded: leftHanded, metronome: metronome)
                    .onChange(of: model.first) { pairText = "\(model.first.name)>\(model.second.name)" }
                    .onChange(of: model.second) { pairText = "\(model.first.name)>\(model.second.name)" }
            }
        }
        .frame(maxWidth: 520)
        .navigationTitle("Chord changes")
        .task {
            guard model == nil else { return }
            let names = pairText.split(separator: ">").map(String.init)
            let first = names.first.flatMap(ChordLibrary.voicing(named:)) ?? ChordLibrary.voicing(named: ChordLibrary.defaultPair.0)!
            let second = names.dropFirst().first.flatMap(ChordLibrary.voicing(named:)) ?? ChordLibrary.voicing(named: ChordLibrary.defaultPair.1)!
            model = ChordChangeViewModel(first: first, second: second, context: context)
            metronome = MetronomeViewModel(bpm: Double(lastBPM))
        }
    }
}
