import SwiftUI
import SwiftData

/// Practice → Rhythm: strum on the click, see how early or late each strike was.
struct RhythmView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.rhythmSubdivision) private var subdivisionRaw = RhythmJudge.Subdivision.quarters.rawValue
    @AppStorage(SettingsKey.rhythmBPM) private var bpm = 80
    @AppStorage(SettingsKey.rhythmBars) private var bars = 4
    @Query(filter: #Predicate<SkillCard> { $0.kind == "rhythm" }) private var cards: [SkillCard]
    @State private var drill: RhythmDrillViewModel?
    @State private var metronome = MetronomeViewModel(bpm: 80)

    private var subdivision: RhythmJudge.Subdivision { RhythmJudge.Subdivision(rawValue: subdivisionRaw) ?? .quarters }

    var body: some View {
        Group {
            if let drill {
                RhythmDrillPanel(model: drill) { end() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("End") { end() } } }
            } else {
                RhythmHomePanel(subdivisionRaw: $subdivisionRaw, bpm: $bpm, bars: $bars, best: cards.first { $0.key == "rhythm:\(subdivision.key)" }?.best) { begin() }
            }
        }
        .frame(maxWidth: 480)
        .onDisappear { end() }
    }

    private func begin() {
        drill = RhythmDrillViewModel(bpm: Double(bpm), subdivision: subdivision, bars: bars, audio: audio, metronome: metronome, context: context)
    }

    private func end() {
        drill?.stop()
        drill = nil
    }
}
