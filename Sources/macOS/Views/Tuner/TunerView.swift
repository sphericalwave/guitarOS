import SwiftUI

/// Tuner in its own utility window (⌘T) or pushed from Tools.
struct TunerView: View {
    @Environment(AudioHub.self) private var audio
    @State private var model: TunerViewModel?

    var body: some View {
        Group {
            if let model {
                TunerPanel(model: model).frame(minWidth: 360, idealWidth: 400)
            }
        }
        .navigationTitle("Tuner")
        .task { if model == nil { model = TunerViewModel(audio: audio, tuning: .standard) } }
    }
}

/// Toolbar button that opens the tuner window from anywhere.
struct TunerToolbarButton: ToolbarContent {
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        ToolbarItem {
            Button { openWindow(id: "tuner") } label: { Label("Tuner", systemImage: "tuningfork") }
                .keyboardShortcut("t")
        }
    }
}
