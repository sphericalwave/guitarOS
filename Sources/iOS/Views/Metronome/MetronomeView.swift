import SwiftUI

struct MetronomeView: View {
    @AppStorage(SettingsKey.lastBPM) private var lastBPM = 100
    @State private var model: MetronomeViewModel?

    var body: some View {
        Group {
            if let model { MetronomePanel(model: model) }
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Metronome")
        .task { if model == nil { model = MetronomeViewModel(bpm: Double(lastBPM)) } }
    }
}
