import SwiftUI

/// Reference fretboard (M1). The note trainer replaces this screen's body in M3.
struct PracticeView: View {
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @State private var naturalsOnly = true
    @State private var showNames = true

    private var fretboard: Fretboard { Fretboard(tuning: Tuning.named(description: tuningText) ?? .standard) }

    var body: some View {
        VStack(spacing: 12) {
            FretboardView(
                fretboard: fretboard,
                fretRange: 0...12,
                leftHanded: leftHanded,
                dots: showNames ? FretboardView.noteNameDots(on: fretboard, frets: 0...12, preferSharps: preferSharps, naturalsOnly: naturalsOnly) : [:]
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
        .navigationTitle("Practice")
        .toolbar {
            ToolbarItem {
                Menu {
                    Toggle("Note names", isOn: $showNames)
                    Toggle("Naturals only", isOn: $naturalsOnly)
                    Toggle("Sharps", isOn: $preferSharps)
                    Toggle("Left-handed", isOn: $leftHanded)
                    Picker("Tuning", selection: $tuningText) {
                        ForEach(Tuning.presets, id: \.description) { Text($0.name).tag($0.description) }
                    }
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}
