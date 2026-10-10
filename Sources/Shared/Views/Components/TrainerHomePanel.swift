import SwiftUI
import SwiftData

/// Practice tab at rest: one Start button, the due count, the mastery heatmap, and the scope behind
/// a disclosure. Identical on both platforms.
struct TrainerHomePanel: View {
    @Query(filter: #Predicate<SkillCard> { $0.kind == "fretPosition" }) private var cards: [SkillCard]
    @Binding var mode: FretboardDrill.Mode
    @Binding var scope: FretboardDrill.Scope
    var fretboard: Fretboard
    var leftHanded: Bool
    var onStart: () -> Void
    @State private var showScope = false

    private var dueCount: Int { cards.filter { $0.srDueDate <= .now }.count }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(FretboardDrill.Mode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)

            FretboardView(fretboard: fretboard, fretRange: scope.frets, leftHanded: leftHanded, dots: masteryDots)
                .frame(maxHeight: .infinity)

            Text(dueCount > 0 ? "\(dueCount) due · \(cards.count) learned" : "\(cards.count) positions learned")
                .font(.footnote).foregroundStyle(.secondary)

            Button {
                onStart()
            } label: {
                Label(mode == .findTheNote ? "Start · play the notes" : "Start · name the notes", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            DisclosureGroup("Customize", isExpanded: $showScope) {
                scopeControls
            }
            .font(.callout)
        }
        .padding()
    }

    private var masteryDots: [FretPosition: FretboardView.Dot] {
        let entries = MasteryMap.entries(cards: cards, tuning: fretboard.tuning)
        var dots: [FretPosition: FretboardView.Dot] = [:]
        for (position, entry) in entries where scope.frets.contains(position.fret) {
            let mastery = MasteryMap.mastery(entry)
            dots[position] = .init(color: entry.isDue ? .orange : Color.green.opacity(0.35 + 0.65 * mastery), label: nil)
        }
        return dots
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Naturals only", isOn: $scope.naturalsOnly)
            Picker("Frets", selection: Binding(get: { scope.frets.upperBound }, set: { scope.frets = 0...$0 })) {
                Text("0–5").tag(5); Text("0–12").tag(12); Text("0–15").tag(15); Text("Whole neck").tag(fretboard.fretCount)
            }
            Picker("Strings", selection: Binding(get: { scope.strings }, set: { scope.strings = $0 })) {
                Text("All").tag(1...6); Text("Low (6–4)").tag(4...6); Text("High (3–1)").tag(1...3)
            }
        }
        .padding(.top, 8)
    }
}
