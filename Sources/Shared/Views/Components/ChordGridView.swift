import SwiftUI

/// A chord diagram: strings vertical (low string left for right-handers), frets horizontal, dots
/// with finger numbers, X/O above the nut, a barre bar, and the base fret when the shape is up the neck.
struct ChordGridView: View {
    var voicing: ChordVoicing
    var leftHanded = false
    var highlightStrings: Set<Int> = []   // 1 = high E, for M6's per-string feedback

    private let fretCount = 4

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            let top: CGFloat = 26
            let bottom: CGFloat = 10
            let gridWidth = size.width - 2 * inset
            let gridHeight = size.height - top - bottom
            let gap = gridWidth / 5
            let fretGap = gridHeight / CGFloat(fretCount)
            let base = voicing.baseFret
            let dotSize = min(gap, fretGap) * 0.68

            func x(stringIndex: Int) -> CGFloat {  // 0 = low string in `frets`
                let column = leftHanded ? 5 - stringIndex : stringIndex
                return inset + CGFloat(column) * gap
            }

            // Nut or base fret
            var nut = Path()
            nut.move(to: CGPoint(x: inset, y: top)); nut.addLine(to: CGPoint(x: inset + gridWidth, y: top))
            context.stroke(nut, with: .color(.primary), lineWidth: base == 1 ? 4 : 1.5)
            if base > 1 {
                context.draw(Text("\(base)fr").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: inset + gridWidth + 2, y: top + fretGap / 2), anchor: .leading)
            }
            // Frets and strings
            for fret in 1...fretCount {
                var path = Path(); let y = top + CGFloat(fret) * fretGap
                path.move(to: CGPoint(x: inset, y: y)); path.addLine(to: CGPoint(x: inset + gridWidth, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
            for index in 0..<6 {
                var path = Path(); let sx = x(stringIndex: index)
                path.move(to: CGPoint(x: sx, y: top)); path.addLine(to: CGPoint(x: sx, y: top + gridHeight))
                context.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 1 + CGFloat(5 - index) * 0.25)
            }
            // Barre
            if let barre = voicing.barre {
                let covered = voicing.frets.indices.filter { voicing.frets[$0] == barre }
                if let lo = covered.min(), let hi = covered.max(), hi > lo {
                    let y = top + (CGFloat(barre - base) + 0.5) * fretGap
                    let xs = [x(stringIndex: lo), x(stringIndex: hi)].sorted()
                    let rect = CGRect(x: xs[0] - dotSize / 2, y: y - dotSize / 2, width: xs[1] - xs[0] + dotSize, height: dotSize)
                    context.fill(Path(roundedRect: rect, cornerRadius: dotSize / 2), with: .color(.accentColor))
                }
            }
            // Dots, X and O
            for (index, fret) in voicing.frets.enumerated() {
                let sx = x(stringIndex: index)
                let string = 6 - index
                let tint: Color = highlightStrings.contains(string) ? .red : .accentColor
                switch fret {
                case nil:
                    context.draw(Text("×").font(.headline).foregroundStyle(.secondary), at: CGPoint(x: sx, y: top - 12))
                case 0?:
                    context.stroke(Path(ellipseIn: CGRect(x: sx - 5, y: top - 17, width: 10, height: 10)), with: .color(.primary), lineWidth: 1.5)
                case let f?:
                    let y = top + (CGFloat(f - base) + 0.5) * fretGap
                    let rect = CGRect(x: sx - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                    if let finger = voicing.fingers?[index] ?? nil {
                        context.draw(Text("\(finger)").font(.system(size: dotSize * 0.55, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: sx, y: y))
                    }
                }
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityLabel("\(voicing.name) chord")
    }
}
