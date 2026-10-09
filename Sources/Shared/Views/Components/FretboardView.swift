import SwiftUI
import MusicTheoryKit

/// A vertical fretboard drawn in a Canvas, with dots on chosen positions.
/// Identical on iOS and macOS; the layout math lives in `FretboardLayout`.
struct FretboardView: View {
    struct Dot: Equatable {
        var color: Color
        var label: String?
        /// Dim dots (e.g. the other notes of a scale) draw hollow.
        var isHollow = false
    }

    var fretboard: Fretboard
    var fretRange: ClosedRange<Int>
    var leftHanded: Bool
    var dots: [FretPosition: Dot]
    var onTap: ((FretPosition) -> Void)? = nil

    private let wood = Color(red: 0.36, green: 0.25, blue: 0.18)
    private let inlay = Color.white.opacity(0.35)

    var body: some View {
        GeometryReader { proxy in
            let layout = FretboardLayout(size: proxy.size, stringCount: fretboard.tuning.stringCount, fretRange: fretRange, leftHanded: leftHanded)
            Canvas { context, _ in
                draw(in: &context, layout: layout)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                if let onTap, let position = layout.position(at: value.location) { onTap(position) }
            })
        }
        .accessibilityLabel("Fretboard")
    }

    private func draw(in context: inout GraphicsContext, layout: FretboardLayout) {
        // Neck
        let neck = CGRect(x: layout.sideInset - 12, y: layout.nutY, width: layout.size.width - 2 * layout.sideInset + 24, height: layout.bottomY - layout.nutY)
        context.fill(Path(roundedRect: neck, cornerRadius: 4), with: .color(wood))

        // Inlays
        for fret in fretRange where fret > fretRange.lowerBound {
            let count = FretboardLayout.inlayCount(fret: fret)
            guard count > 0 else { continue }
            let y = (layout.fretY(fret - 1) + layout.fretY(fret)) / 2
            let xs: [CGFloat] = count == 1 ? [neck.midX] : [neck.midX - neck.width * 0.22, neck.midX + neck.width * 0.22]
            for x in xs {
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(inlay))
            }
        }

        // Fret wires (nut is thicker when fret 0 is shown)
        for fret in fretRange {
            let y = layout.fretY(fret)
            var path = Path()
            path.move(to: CGPoint(x: neck.minX, y: y))
            path.addLine(to: CGPoint(x: neck.maxX, y: y))
            let isNut = fret == 0
            context.stroke(path, with: .color(isNut ? .primary.opacity(0.9) : .gray.opacity(0.8)), lineWidth: isNut ? 5 : 2)
        }

        // Strings: thicker for lower strings
        for string in 1...fretboard.tuning.stringCount {
            let x = layout.stringX(string)
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.nutY))
            path.addLine(to: CGPoint(x: x, y: layout.bottomY))
            let width = 1 + CGFloat(string - 1) * 0.45
            context.stroke(path, with: .color(.primary.opacity(0.75)), lineWidth: width)
        }

        // Dots
        for (position, dot) in dots where fretRange.contains(position.fret) || position.fret == 0 {
            let center = layout.dotCenter(position)
            let diameter = layout.dotDiameter(position)
            let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            if dot.isHollow {
                context.stroke(Path(ellipseIn: rect), with: .color(dot.color), lineWidth: 2)
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(dot.color))
            }
            if let label = dot.label {
                let text = Text(label).font(.system(size: diameter * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(dot.isHollow ? dot.color : .white)
                context.draw(context.resolve(text), at: center)
            }
        }
    }
}

extension FretboardView {
    /// Note names on every position, for the reference fretboard.
    static func noteNameDots(on fretboard: Fretboard, frets: ClosedRange<Int>, preferSharps: Bool, naturalsOnly: Bool) -> [FretPosition: Dot] {
        var dots: [FretPosition: Dot] = [:]
        for position in fretboard.allPositions(frets: frets, naturalsOnly: naturalsOnly) {
            let pitchClass = fretboard.pitchClass(at: position)
            let isNatural = Scale(root: 0, kind: .major).contains(pitchClass: pitchClass)
            dots[position] = Dot(color: isNatural ? .accentColor : .secondary, label: PitchName.name(forPitchClass: pitchClass, preferSharps: preferSharps))
        }
        return dots
    }
}
