import SwiftUI

/// Tuner as a sheet from any tab, or pushed from Tools.
struct TunerView: View {
    @Environment(AudioHub.self) private var audio
    @State private var model: TunerViewModel?

    var body: some View {
        ScrollView {
            if let model {
                TunerPanel(model: model)
            }
        }
        .navigationTitle("Tuner")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model == nil { model = TunerViewModel(audio: audio, tuning: .standard) } }
    }
}

/// Toolbar button that opens the tuner from anywhere (guitarists retune mid-session).
struct TunerToolbarButton: ToolbarContent {
    @State private var isPresented = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { isPresented = true } label: { Label("Tuner", systemImage: "tuningfork") }
                .sheet(isPresented: $isPresented) {
                    NavigationStack {
                        TunerView()
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } } }
                    }
                }
        }
    }
}
