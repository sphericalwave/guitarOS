import Testing
import CoreGraphics
@testable import guitar

struct FretboardLayoutTests {
    let layout = FretboardLayout(size: CGSize(width: 300, height: 800), fretRange: 0...12)

    @Test func fretsGetCloserUpTheNeck() {
        let gaps = (1...12).map { layout.fretY($0) - layout.fretY($0 - 1) }
        #expect(gaps == gaps.sorted(by: >))
        #expect(layout.fretY(0) == layout.nutY)
        #expect(abs(layout.fretY(12) - layout.bottomY) < 0.001)
    }

    @Test func rightHandedPutsTheLowStringOnTheLeft() {
        #expect(layout.stringX(6) < layout.stringX(1))
        var mirrored = layout
        mirrored.leftHanded = true
        #expect(mirrored.stringX(6) > mirrored.stringX(1))
        #expect(mirrored.stringX(6) == layout.stringX(1))
    }

    @Test func dotsSitBetweenTheirFretWires() {
        let c = layout.dotCenter(FretPosition(string: 3, fret: 5))
        #expect(c.y > layout.fretY(4) && c.y < layout.fretY(5))
        #expect(c.x == layout.stringX(3))
        // Open strings float above the nut.
        #expect(layout.dotCenter(FretPosition(string: 1, fret: 0)).y < layout.nutY)
    }

    @Test func tapHitsTheDotItLandsOn() {
        for position in [FretPosition(string: 6, fret: 1), FretPosition(string: 1, fret: 12), FretPosition(string: 4, fret: 0)] {
            #expect(layout.position(at: layout.dotCenter(position)) == position)
        }
        #expect(layout.position(at: CGPoint(x: -1, y: 10)) == nil)
    }

    @Test func inlaysOnTheUsualFrets() {
        #expect((1...24).filter { FretboardLayout.inlayCount(fret: $0) == 1 } == [3, 5, 7, 9, 15, 17, 19, 21])
        #expect(FretboardLayout.inlayCount(fret: 12) == 2)
        #expect(FretboardLayout.inlayCount(fret: 24) == 2)
        #expect(FretboardLayout.inlayCount(fret: 0) == 0)
    }
}
