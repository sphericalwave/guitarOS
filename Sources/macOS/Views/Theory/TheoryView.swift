import SwiftUI
import SwiftData

/// Practice → Theory: silent flashcards generated from the theory engine.
struct TheoryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.preferSharps) private var preferSharps = true
    @AppStorage(SettingsKey.theoryKind) private var kindRaw = TheoryDrill.Kind.intervalNote.rawValue
    @Query(filter: #Predicate<SkillCard> { $0.key.starts(with: "theory:") }) private var cards: [SkillCard]
    @State private var drill: TheoryDrillViewModel?

    private var kind: TheoryDrill.Kind { TheoryDrill.Kind(rawValue: kindRaw) ?? .intervalNote }

    var body: some View {
        Group {
            if let drill {
                TheoryDrillPanel(model: drill) { end() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("End") { end() } } }
            } else {
                TheoryHomePanel(kindRaw: $kindRaw, dueCount: cards.filter { $0.srDueDate <= .now }.count) { begin() }
            }
        }
        .frame(maxWidth: 480)
        .onDisappear { end() }
    }

    private func begin() {
        let model = TheoryDrillViewModel(kind: kind, preferSharps: preferSharps, cards: CardStore(context: context))
        model.start()
        drill = model
    }

    private func end() {
        drill?.stop()
        drill = nil
    }
}
