import Foundation
import Testing
import MusicTheoryKit
import PlayAlongKit
@testable import guitar

struct ScaleShapeTests {
    let aMinorPentatonic = Scale(root: 9, kind: .minorPentatonic)
    let cMajor = Scale(root: 0, kind: .major)

    @Test func aMinorPentatonicBoxesSitWhereGuitaristsExpect() {
        let boxes = ScaleShapes.caged(aMinorPentatonic)
        #expect(boxes.map(\.lowFret) == [0, 2, 5, 7, 9])
        #expect(boxes.map(\.shape) == ["C", "A", "G", "E", "D"])
        #expect(boxes.map(\.index) == [1, 2, 3, 4, 5])
        // "Box 1" (frets 5–8): two notes per string, root on the low E at fret 5.
        let box = boxes[2]
        #expect(box.positions.count == 12)
        #expect(box.positions.first == FretPosition(string: 6, fret: 5) && box.isRoot(box.positions[0]))
        #expect(box.positions.allSatisfy { box.frets.contains($0.fret) && aMinorPentatonic.contains(pitchClass: Int(box.pitch(at: $0)) % 12) })
        #expect(box.positions.last == FretPosition(string: 1, fret: 8))
    }

    @Test func cMajorEShapeIsTheSeventhPositionBox() {
        let position = ScaleShapes.caged(cMajor).first { $0.shape == "E" }!
        #expect(position.lowFret == 7 && position.index == 4)
        // Every note from B2 (string 6 fret 7) to D5 (string 1 fret 10), ascending with no gaps in the scale.
        let pitches = position.positions.map { Int(position.pitch(at: $0)) }
        #expect(pitches == pitches.sorted() && pitches.first == 47 && pitches.last == 74)
        #expect(Set(pitches).count == pitches.count, "no pitch twice")
        #expect(position.positions.count == 17)
        #expect(position.degree(of: FretPosition(string: 6, fret: 8)) == 1 && position.degree(of: FretPosition(string: 5, fret: 8)) == 4)
    }

    @Test func openPositionIncludesOpenStrings() {
        let open = ScaleShapes.caged(cMajor)[0]
        #expect(open.lowFret == 0 && open.shape == "C")
        #expect(open.positions.contains(FretPosition(string: 6, fret: 0)))
        #expect(open.title == "Position 1 · C shape")
    }

    @Test func sequenceGoesUpAndBackDown() {
        let box = ScaleShapes.caged(aMinorPentatonic)[2]
        let sequence = box.sequence
        #expect(sequence.count == 23)
        #expect(sequence.first == box.positions.first && sequence.last == box.positions.first)
        #expect(sequence[11] == box.positions.last)
    }

    @Test func keysRoundTrip() {
        let box = ScaleShapes.caged(aMinorPentatonic)[2]
        #expect(box.key == "scale:9:minorPentatonic:3")
        #expect(ScaleShapes.position(forKey: box.key) == box)
        #expect(ScaleShapes.position(forKey: "scale:2:dorian:2")?.scale.kind == .mode(.dorian))
        #expect(ScaleShapes.position(forKey: "scale:x") == nil)
        for kind in Scale.Kind.common { #expect(ScaleShapes.kind(forKey: ScaleShapes.kindKey(kind)) == kind) }
    }

    @Test func dropDMovesTheBoxes() {
        let boxes = ScaleShapes.caged(cMajor, tuning: .dropD)
        // The low string is D now, so C's E-shape root fret moves from 8 to 10 and the window from 7 to 9.
        #expect(boxes.first { $0.shape == "E" }?.lowFret == 9)
    }
}

struct ScaleDrillTests {
    @Test func expectedNotesFollowTheClickAfterACountIn() {
        let notes = ScaleDrill.expectedNotes(pitches: [57, 60, 62], bpm: 120)
        #expect(notes.map(\.id) == [0, 1, 2])
        #expect(notes.map(\.time) == [2.0, 2.5, 3.0])
        #expect(notes.map(\.pitch) == [57, 60, 62])
    }

    @Test func cleanPassesSpeedUpAndGradeWell() {
        let clean = ScaleDrill.Result(mode: .timed, bpm: 80, notes: 20, hits: 19, missed: 1, extras: 2, seconds: 20)
        #expect(clean.isClean && ScaleDrill.nextBPM(after: clean) == 85 && ScaleDrill.quality(clean) == 4)
        let perfect = ScaleDrill.Result(mode: .timed, bpm: 80, notes: 20, hits: 20, missed: 0, extras: 0, seconds: 20)
        #expect(ScaleDrill.quality(perfect) == 5)
        let rough = ScaleDrill.Result(mode: .timed, bpm: 80, notes: 20, hits: 14, missed: 6, extras: 0, seconds: 20)
        #expect(!rough.isClean && ScaleDrill.nextBPM(after: rough) == 80 && ScaleDrill.quality(rough) == 3)
        let sloppy = ScaleDrill.Result(mode: .timed, bpm: 80, notes: 20, hits: 19, missed: 1, extras: 9, seconds: 20)
        #expect(!sloppy.isClean, "too many stray notes")
        #expect(ScaleDrill.quality(ScaleDrill.Result(mode: .wait, bpm: 0, notes: 20, hits: 5, missed: 15, extras: 0, seconds: 60)) == 1)
    }

    @Test func routineIncludesAScaleBlock() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 0, learnedFretCards: 30, scaleKey: "scale:9:minorPentatonic:3"))
        let scale = routine.first { $0.kind == .scale }
        #expect(scale?.detail == "scale:9:minorPentatonic:3" && scale?.minutes == 3)
        #expect(scale?.title == "A minor pentatonic · position 3")
        #expect(RoutineBuilder.totalMinutes(routine) == 20)
        // Short days skip it.
        #expect(RoutineBuilder.routine(.init(goalMinutes: 5, dueFretCards: 0, learnedFretCards: 30)).first { $0.kind == .scale } == nil)
    }
}
