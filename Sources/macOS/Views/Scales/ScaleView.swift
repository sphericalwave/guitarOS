import SwiftUI
import SwiftData

/// Practice → Scales: pick a scale and CAGED position, then play it with or without the click.
struct ScaleView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.tuning) private var tuningText = Tuning.standard.description
    @AppStorage(SettingsKey.scaleRoot) private var root = 9
    @AppStorage(SettingsKey.scaleKind) private var kindKey = "minorPentatonic"
    @AppStorage(SettingsKey.scalePosition) private var positionIndex = 3
    @AppStorage(SettingsKey.scaleMode) private var modeRaw = ScaleDrill.Mode.wait.rawValue
    @AppStorage(SettingsKey.scaleBPM) private var bpm = Int(ScaleDrill.defaultBPM)
    @Query(filter: #Predicate<SkillCard> { $0.kind == "scaleShape" }) private var cards: [SkillCard]
    @State private var drill: ScaleDrillViewModel?
    @State private var metronome = MetronomeViewModel(bpm: ScaleDrill.defaultBPM)

    private var fretboard: Fretboard { Fretboard(tuning: Tuning.named(description: tuningText) ?? .standard) }
    private var mode: Binding<ScaleDrill.Mode> { Binding(get: { ScaleDrill.Mode(rawValue: modeRaw) ?? .wait }, set: { modeRaw = $0.rawValue }) }
    private var position: ScalePosition? { ScaleShapes.position(forKey: "scale:\(root):\(kindKey):\(positionIndex)", tuning: fretboard.tuning) }

    var body: some View {
        Group {
            if let drill {
                ScaleDrillPanel(model: drill, fretboard: fretboard, leftHanded: leftHanded, preferSharps: preferSharps) { end() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("End") { end() } } }
            } else {
                ScaleHomePanel(root: $root, kindKey: $kindKey, positionIndex: $positionIndex, mode: mode, bpm: $bpm, fretboard: fretboard,
                               leftHanded: leftHanded, preferSharps: preferSharps, best: cards.first { $0.key == position?.key }?.best) { begin() }
            }
        }
        .frame(maxWidth: 480)
        .onDisappear { end() }
    }

    private func begin() {
        guard let position else { return }
        drill = ScaleDrillViewModel(position: position, mode: mode.wrappedValue, bpm: Double(bpm), audio: audio, context: context, metronome: metronome)
    }

    private func end() {
        if let drill, case .finished(let result) = drill.phase, result.mode == .timed { bpm = Int(ScaleDrill.nextBPM(after: result)) }
        drill?.stop()
        drill = nil
    }
}
