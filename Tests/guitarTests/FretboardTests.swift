import Testing
@testable import guitar

struct FretboardTests {
    let board = Fretboard()

    @Test func e4LivesInThreePlacesBelowTheTwelfthFret() {
        #expect(board.positions(of: 64, frets: 0...12) == [
            FretPosition(string: 3, fret: 9), FretPosition(string: 2, fret: 5), FretPosition(string: 1, fret: 0),
        ])
    }

    @Test func pitchAndPitchClass() {
        #expect(board.pitch(at: FretPosition(string: 5, fret: 3)) == 48)  // C3
        #expect(board.pitchClass(at: FretPosition(string: 5, fret: 3)) == 0)
    }

    @Test func pitchClassPositionsRespectScope() {
        let cs = board.positions(ofPitchClass: 0, frets: 0...5, strings: 5...6)
        #expect(cs == [FretPosition(string: 5, fret: 3)])  // C on the low E is fret 8, out of scope
    }

    @Test func naturalsOnlyDropsAccidentals() {
        let all = board.allPositions(frets: 0...12)
        let naturals = board.allPositions(frets: 0...12, naturalsOnly: true)
        #expect(all.count == 6 * 13)
        #expect(naturals.count < all.count)
        #expect(naturals.allSatisfy { [0, 2, 4, 5, 7, 9, 11].contains(board.pitchClass(at: $0)) })
    }

    @Test func positionKeysRoundTrip() {
        let p = FretPosition(string: 3, fret: 7)
        #expect(p.key == "s3f7")
        #expect(FretPosition(key: "s3f7") == p)
        #expect(FretPosition(key: "x") == nil)
    }

    @Test func rangeCoversTheWholeNeck() {
        #expect(board.pitchRange == 40...86)
    }
}
