import SwiftUI
import MusicTheoryKit

/// Scales at rest: pick the scale and CAGED position, see the box, choose wait or click, start.
/// Identical on both platforms.
struct ScaleHomePanel: View {
    @Binding var root: Int
    @Binding var kindKey: String
    @Binding var positionIndex: Int
    @Binding var mode: ScaleDrill.Mode
    @Binding var bpm: Int
    var fretboard: Fretboard
    var leftHanded: Bool
    var preferSharps: Bool
    var best: Double?
    var onStart: () -> Void

    private var scale: Scale { Scale(root: root, kind: ScaleShapes.kind(forKey: kindKey) ?? .minorPentatonic) }
    private var positions: [ScalePosition] { ScaleShapes.caged(scale, tuning: fretboard.tuning) }
    private var position: ScalePosition { positions.first { $0.index == positionIndex } ?? positions[0] }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Picker("Root", selection: $root) {
                    ForEach(0..<12, id: \.self) { Text(PitchName.name(forPitchClass: $0, preferSharps: preferSharps)).tag($0) }
                }
                Picker("Scale", selection: $kindKey) {
                    ForEach(Scale.Kind.common, id: \.self) { Text($0.name).tag(ScaleShapes.kindKey($0)) }
                }
            }
            .labelsHidden()
            Picker("Position", selection: $positionIndex) {
                ForEach(positions) { Text("\($0.index) · \($0.shape)").tag($0.index) }
            }
            .pickerStyle(.segmented)

            FretboardView(fretboard: fretboard, fretRange: ScaleHomePanel.visibleFrets(position, fretboard: fretboard), leftHanded: leftHanded,
                          dots: ScaleHomePanel.dots(position, preferSharps: preferSharps))
                .frame(maxHeight: .infinity)

            Text(position.title + (best.map { " · best \(Int($0)) BPM" } ?? ""))
                .font(.footnote).foregroundStyle(.secondary)

            Picker("Mode", selection: $mode) {
                ForEach(ScaleDrill.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if mode == .timed {
                Stepper("\(bpm) BPM", value: $bpm, in: Int(ClickSchedule.bpmRange.lowerBound)...Int(ClickSchedule.bpmRange.upperBound), step: Int(ScaleDrill.bpmStep))
                    .font(.title3.monospacedDigit())
            }
            Button {
                onStart()
            } label: {
                Label(mode == .wait ? "Start · play the box" : "Start · \(bpm) BPM", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    /// The box plus a fret either side, or from the nut when it's low.
    static func visibleFrets(_ position: ScalePosition, fretboard: Fretboard) -> ClosedRange<Int> {
        let low = max(0, position.lowFret - 1)
        return low...min(fretboard.fretCount, position.frets.upperBound + 1)
    }

    /// Roots in the accent colour, the rest hollow, labelled with their degree.
    static func dots(_ position: ScalePosition, preferSharps: Bool) -> [FretPosition: FretboardView.Dot] {
        var dots: [FretPosition: FretboardView.Dot] = [:]
        for place in position.positions {
            let isRoot = position.isRoot(place)
            dots[place] = .init(color: isRoot ? .accentColor : .secondary, label: isRoot ? PitchName.name(forPitchClass: position.scale.root, preferSharps: preferSharps) : position.degree(of: place).map(String.init), isHollow: !isRoot)
        }
        return dots
    }
}
