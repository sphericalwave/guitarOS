import SwiftUI
import SwiftData

/// Fretboard note trainer: home (start, heatmap, scope) and the drill itself.
struct PracticeView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.drillMode) private var modeRaw = FretboardDrill.Mode.findTheNote.rawValue
    @AppStorage(SettingsKey.drillScope) private var scopeData = Data()
    @State private var drill: FretboardDrillViewModel?
    @AppStorage(SettingsKey.practicePage) private var page = "notes"

    private var fretboard: Fretboard { Fretboard(tuning: Tuning.named(description: tuningText) ?? .standard) }
    private var mode: Binding<FretboardDrill.Mode> {
        Binding(get: { FretboardDrill.Mode(rawValue: modeRaw) ?? .findTheNote }, set: { modeRaw = $0.rawValue })
    }
    private var scope: Binding<FretboardDrill.Scope> {
        Binding(
            get: { (try? JSONDecoder().decode(FretboardDrill.Scope.self, from: scopeData)) ?? .default },
            set: { scopeData = (try? JSONEncoder().encode($0)) ?? Data() }
        )
    }

    var body: some View {
        Group {
            if let drill {
                DrillPanel(model: drill, leftHanded: leftHanded, preferSharps: preferSharps, scope: scope.wrappedValue) { end() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("End") { end() } }
                    }
            } else if page == "chords" {
                ChordChangeView()
            } else {
                TrainerHomePanel(mode: mode, scope: scope, fretboard: fretboard, leftHanded: leftHanded) { begin() }
            }
        }
        .toolbar {
            if drill == nil {
                ToolbarItem(placement: .principal) {
                    Picker("Practice", selection: $page) { Text("Notes").tag("notes"); Text("Chords").tag("chords") }
                        .pickerStyle(.segmented).frame(width: 200)
                }
            }
        }
        .frame(maxWidth: 480)
        .navigationTitle("Practice")
        .onDisappear { end() }
    }

    private func begin() {
        let model = FretboardDrillViewModel(fretboard: fretboard, mode: mode.wrappedValue, audio: audio, cards: CardStore(context: context))
        model.start(scope: scope.wrappedValue)
        drill = model
    }

    private func end() {
        drill?.stop()
        drill = nil
    }
}
