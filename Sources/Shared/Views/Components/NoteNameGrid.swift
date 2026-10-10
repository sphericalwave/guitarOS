import SwiftUI
import MusicTheoryKit

/// Twelve big buttons for naming a note silently. 4×3 so every target is thumb-sized.
struct NoteNameGrid: View {
    var preferSharps: Bool
    var isEnabled: Bool
    var onPick: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(0..<12, id: \.self) { pitchClass in
                Button {
                    onPick(pitchClass)
                } label: {
                    Text(PitchName.name(forPitchClass: pitchClass, preferSharps: preferSharps))
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
            }
        }
    }
}
