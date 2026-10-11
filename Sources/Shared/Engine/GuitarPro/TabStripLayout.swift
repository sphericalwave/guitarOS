import CoreGraphics
import Foundation

/// Geometry of the scrolling tab strip: a band for chord names on top, then one line per string with the
/// highest string uppermost (as tab is read), music flowing right to left past a fixed playhead.
nonisolated struct TabStripLayout: Equatable {
    /// Where the playhead sits across the width.
    static let playheadFraction: CGFloat = 0.3

    let size: CGSize
    /// Seconds of music across the strip.
    let window: TimeInterval
    let stringCount: Int
    /// Points reserved at the top for chord names and markers.
    let chordBand: CGFloat
    let lineSpacing: CGFloat
    /// y of string 1 (the highest, drawn at the top).
    let firstLineY: CGFloat

    init(size: CGSize, window: TimeInterval, stringCount: Int, chordBand: CGFloat = 22) {
        self.size = size
        self.window = max(window, 0.5)
        self.stringCount = max(stringCount, 1)
        self.chordBand = min(max(chordBand, 0), size.height * 0.35)
        let usable = max(size.height - self.chordBand, 1)
        // One spacing of margin above and below the lines.
        lineSpacing = usable / CGFloat(self.stringCount + 1)
        firstLineY = self.chordBand + lineSpacing
    }

    var pixelsPerSecond: CGFloat { size.width / window }
    var playheadX: CGFloat { size.width * Self.playheadFraction }

    func x(forTime time: TimeInterval, now: TimeInterval) -> CGFloat {
        playheadX + CGFloat(time - now) * pixelsPerSecond
    }

    /// y of a string's line, 1 = highest string.
    func y(string: Int) -> CGFloat {
        firstLineY + CGFloat(min(max(string, 1), stringCount) - 1) * lineSpacing
    }

    /// The music visible at a moment: a little before the playhead, more after it.
    func visibleRange(now: TimeInterval) -> ClosedRange<TimeInterval> {
        let before = window * Double(Self.playheadFraction)
        return (now - before)...(now + window - before)
    }

    /// Fret numbers sit in a box just under a line's height.
    var fretFontSize: CGFloat { max(lineSpacing * 0.72, 9) }
    var fretBoxSize: CGSize { CGSize(width: lineSpacing * 1.1, height: lineSpacing * 0.9) }
}
