import SwiftUI
import SwiftData

/// Practice → Ear: intervals, chord qualities, scale degrees, play-back.
struct EarView: View {
    @Environment(AudioHub.self) private var audio
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.earMode) private var modeRaw = EarDrill.Mode.interval.rawValue
    @AppStorage(SettingsKey.earLevel) private var level = 1
    @Query(filter: #Predicate<SkillCard> { $0.key.starts(with: "ear:") }) private var cards: [SkillCard]
    @State private var drill: EarDrillViewModel?
    @State private var tones = TonePlayer()

    private var mode: EarDrill.Mode { EarDrill.Mode(rawValue: modeRaw) ?? .interval }

    var body: some View {
        Group {
            if let drill {
                EarDrillPanel(model: drill) { end() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("End") { end() } } }
            } else {
                EarHomePanel(modeRaw: $modeRaw, level: $level, dueCount: cards.filter { $0.kind == mode.kind.rawValue && $0.srDueDate <= .now }.count) { begin() }
            }
        }
        .frame(maxWidth: 480)
        .onDisappear { end() }
    }

    private func begin() {
        let model = EarDrillViewModel(mode: mode, level: level, audio: audio, tones: tones, cards: CardStore(context: context))
        model.start()
        drill = model
    }

    private func end() {
        drill?.stop()
        drill = nil
    }
}
