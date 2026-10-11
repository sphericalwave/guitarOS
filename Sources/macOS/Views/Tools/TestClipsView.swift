import SwiftUI

/// Tools → Record a test clip.
struct TestClipsView: View {
    @Environment(AudioHub.self) private var audio
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.chordPair) private var pairText = "C>G"
    @State private var model: TestClipViewModel?

    var body: some View {
        Group {
            if let model {
                TestClipPanel(model: model, tuning: Tuning.named(description: tuningText) ?? .standard)
            }
        }
        .frame(maxWidth: 560)
        .navigationTitle("Test clips")
        .task {
            guard model == nil else { return }
            let name = pairText.split(separator: ">").first.map(String.init) ?? ChordLibrary.defaultPair.0
            model = TestClipViewModel(audio: audio, chord: ChordLibrary.voicing(named: name) ?? ChordLibrary.voicings[0])
        }
    }
}
