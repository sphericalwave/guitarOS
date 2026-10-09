import Foundation

/// Where strings, frets and dots sit in a rectangle. Vertical neck, nut at the top, as you see it
/// looking down at the guitar. Pure geometry so it's unit-tested; `FretboardView` draws it.
nonisolated struct FretboardLayout: Equatable, Sendable {
    var size: CGSize
    var stringCount: Int
    /// Frets shown, e.g. 0...12. Fret 0 is the nut; its "space" is where open-string dots go.
    var fretRange: ClosedRange<Int>
    /// Mirrors string order so the low string sits on the right.
    var leftHanded: Bool
    /// Horizontal padding so the outer strings aren't on the edge.
    var sideInset: CGFloat = 24
    /// Room above the nut for open-string dots.
    var nutInset: CGFloat = 36

    /// Real fret spacing shrinks by 2^(-1/12) per fret; this blends it with even spacing so a
    /// 0...22 view stays readable near the body. 1 = real, 0 = even.
    var realism: CGFloat = 0.6

    init(size: CGSize, stringCount: Int = 6, fretRange: ClosedRange<Int> = 0...12, leftHanded: Bool = false) {
        self.size = size
        self.stringCount = stringCount
        self.fretRange = fretRange
        self.leftHanded = leftHanded
    }

    var nutY: CGFloat { nutInset }
    var bottomY: CGFloat { size.height - 8 }

    /// Fret wire y for a fret number in range. `fretY(fretRange.lowerBound)` is the top wire (the nut
    /// when the range starts at 0).
    func fretY(_ fret: Int) -> CGFloat {
        let first = fretRange.lowerBound, last = fretRange.upperBound
        guard last > first else { return nutY }
        let real = { (f: Int) -> CGFloat in 1 - pow(2, -CGFloat(f) / 12) }
        let realFraction = (real(fret) - real(first)) / (real(last) - real(first))
        let evenFraction = CGFloat(fret - first) / CGFloat(last - first)
        let fraction = realism * realFraction + (1 - realism) * evenFraction
        return nutY + fraction * (bottomY - nutY)
    }

    /// x of a string by guitarist number (1 = high E, on the right for right-handers).
    func stringX(_ string: Int) -> CGFloat {
        let usable = size.width - 2 * sideInset
        let gap = stringCount > 1 ? usable / CGFloat(stringCount - 1) : 0
        let indexFromLeft = leftHanded ? string - 1 : stringCount - string
        return sideInset + CGFloat(indexFromLeft) * gap
    }

    /// Where a dot for this position goes: between the fret wires, or above the nut for fret 0.
    func dotCenter(_ position: FretPosition) -> CGPoint {
        let x = stringX(position.string)
        if position.fret == 0 || position.fret < fretRange.lowerBound {
            return CGPoint(x: x, y: nutY / 2)
        }
        let top = fretY(max(position.fret - 1, fretRange.lowerBound))
        return CGPoint(x: x, y: (top + fretY(position.fret)) / 2)
    }

    /// Fret-wise, a dot is sized by the gap it sits in; capped so open-string dots match.
    func dotDiameter(_ position: FretPosition) -> CGFloat {
        let gapY: CGFloat
        if position.fret <= fretRange.lowerBound {
            gapY = nutY
        } else {
            gapY = fretY(position.fret) - fretY(position.fret - 1)
        }
        let gapX = stringCount > 1 ? (size.width - 2 * sideInset) / CGFloat(stringCount - 1) : size.width
        return min(gapX, gapY) * 0.72
    }

    /// Frets that get an inlay dot, with 12 and 24 doubled.
    static func inlayCount(fret: Int) -> Int {
        switch fret % 12 {
        case 0: fret == 0 ? 0 : 2
        case 3, 5, 7, 9: 1
        default: 0
        }
    }

    /// The position under a touch, or nil off the neck. Snaps to the nearest string and the gap
    /// the point falls in; above the nut counts as the open string.
    func position(at point: CGPoint) -> FretPosition? {
        guard (0...size.width).contains(point.x), (0...size.height).contains(point.y) else { return nil }
        let string = (1...stringCount).min { abs(stringX($0) - point.x) < abs(stringX($1) - point.x) } ?? 1
        if point.y < fretY(fretRange.lowerBound) {
            return fretRange.lowerBound == 0 ? FretPosition(string: string, fret: 0) : nil
        }
        for fret in (fretRange.lowerBound + 1)...max(fretRange.lowerBound + 1, fretRange.upperBound) where point.y <= fretY(fret) {
            return FretPosition(string: string, fret: fret)
        }
        return nil
    }
}
