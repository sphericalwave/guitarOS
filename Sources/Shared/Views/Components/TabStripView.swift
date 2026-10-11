import SwiftUI

/// The tab scrolling past a playhead: string lines, bar lines, fret numbers coloured by how they were judged,
/// chord names and markers above. Identical on both platforms; geometry lives in `TabStripLayout`.
struct TabStripView: View {
    var timeline: TabTimeline
    var track: Int
    var stringCount: Int
    var position: TimeInterval
    /// Timeline note id → hit (true) or missed (false).
    var results: [Int: Bool]
    /// Pitches the wait gate is holding for.
    var required: Set<UInt8>
    var window: TimeInterval = 4

    var body: some View {
        GeometryReader { proxy in
            let layout = TabStripLayout(size: proxy.size, window: window, stringCount: stringCount)
            Canvas { context, _ in
                draw(in: &context, layout: layout)
            }
        }
        .accessibilityLabel("Tab")
    }

    private func draw(in context: inout GraphicsContext, layout: TabStripLayout) {
        let range = layout.visibleRange(now: position)

        // String lines
        for string in 1...layout.stringCount {
            var path = Path()
            let y = layout.y(string: string)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.size.width, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
        }

        // Bar lines, markers and chord names
        let top = layout.firstLineY, bottom = layout.y(string: layout.stringCount)
        for (index, measure) in timeline.measures.enumerated() where range.contains(measure.start) {
            let x = layout.x(forTime: measure.start, now: position)
            var path = Path()
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
            context.draw(Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: top - layout.lineSpacing * 0.55), anchor: .leading)
            if let marker = measure.marker {
                context.draw(Text(marker).font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: layout.chordBand * 0.35), anchor: .leading)
            }
        }
        for beat in timeline.beats where beat.track == track && range.contains(beat.start) {
            if let chord = beat.chordName, !chord.isEmpty {
                context.draw(Text(chord).font(.caption.bold()), at: CGPoint(x: layout.x(forTime: beat.start, now: position), y: layout.chordBand * 0.75), anchor: .leading)
            }
        }

        // Playhead
        var playhead = Path()
        playhead.move(to: CGPoint(x: layout.playheadX, y: layout.chordBand))
        playhead.addLine(to: CGPoint(x: layout.playheadX, y: layout.size.height))
        context.stroke(playhead, with: .color(.accentColor.opacity(0.6)), lineWidth: 2)

        // Notes
        let box = layout.fretBoxSize
        for note in timeline.notes where note.track == track && range.contains(note.start) {
            let x = layout.x(forTime: note.start, now: position)
            let y = layout.y(string: note.string)
            let colour: Color
            if let hit = results[note.id] { colour = hit ? .green : .red }
            else if required.contains(note.pitch) && abs(note.start - position) < 0.05 { colour = .orange }
            else if note.start < position { colour = .secondary }
            else { colour = .primary }
            let rect = CGRect(x: x - box.width / 2, y: y - box.height / 2, width: box.width, height: box.height)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .style(.background))
            let label = note.isDead ? "x" : (note.isTie ? "(\(note.fret))" : "\(note.fret)")
            context.draw(Text(label).font(.system(size: layout.fretFontSize, weight: .semibold, design: .rounded)).foregroundStyle(colour), at: CGPoint(x: x, y: y))
            if note.effects.contains(.bend) || note.effects.contains(.slide) || note.effects.contains(.hammerOn) {
                let mark = note.effects.contains(.bend) ? "b" : (note.effects.contains(.slide) ? "/" : "h")
                context.draw(Text(mark).font(.system(size: layout.fretFontSize * 0.7)).foregroundStyle(.secondary), at: CGPoint(x: x + box.width * 0.75, y: y - box.height * 0.4))
            }
            if note.effects.contains(.palmMute) {
                context.draw(Text("PM").font(.system(size: layout.fretFontSize * 0.55)).foregroundStyle(.secondary), at: CGPoint(x: x, y: bottom + layout.lineSpacing * 0.55))
            }
        }
    }
}
