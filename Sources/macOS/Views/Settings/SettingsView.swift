import SwiftUI

/// The guitar and the goal. Tuning and reference A also live on the tuner; they're mirrored to iCloud.
struct SettingsView: View {
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 20
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.autoCountChords) private var autoCountChords = false

    var body: some View {
        Form {
            Section("Practice") {
                Stepper("Daily goal: \(goalMinutes) min", value: $goalMinutes, in: 5...120, step: 5)
            }
            Section("Guitar") {
                Picker("Tuning", selection: $tuningText) {
                    ForEach(Tuning.presets, id: \.description) { Text($0.name).tag($0.description) }
                }
                Toggle("Left-handed (mirror the neck)", isOn: $leftHanded)
                Toggle("Spell with sharps", isOn: $preferSharps)
            }
            Section {
                Toggle("Auto-count chord changes (beta)", isOn: $autoCountChords)
            } footer: {
                Text("The mic listens for each strum and counts the clean changes; the grid shows which string didn't ring. Self-counting stays the default until this proves itself on recorded test clips (Tools → Record a test clip).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
