import Foundation
import Testing
import MusicTheoryKit
@testable import guitar

struct ClickScheduleTests {
    let schedule = ClickSchedule(bpm: 120, beatsPerBar: 4, sampleRate: 48_000)

    @Test func beatsLandEveryHalfSecondAt120() {
        #expect(schedule.samplesPerBeat == 24_000)
        #expect(schedule.sample(ofBeat: 3, start: 1000) == 73_000)
        let clicks = schedule.clicks(in: 0..<100_000, start: 0)
        #expect(clicks.map(\.sample) == [0, 24_000, 48_000, 72_000, 96_000])
        #expect(clicks.map(\.isAccent) == [true, false, false, false, true])
    }

    @Test func bufferBoundariesNeverDropOrDoubleAClick() {
        var all: [Int] = []
        for start in stride(from: 0, to: 480_000, by: 512) {
            all += schedule.clicks(in: start..<(start + 512), start: 0).map(\.sample)
        }
        #expect(all == Array(stride(from: 0, through: 480_000, by: 24_000)))  // the last buffer runs past 480 000
    }

    @Test func fractionalTemposStayOnTheGrid() {
        let odd = ClickSchedule(bpm: 97, beatsPerBar: 3, sampleRate: 44_100)
        let hundredth = odd.sample(ofBeat: 100, start: 0)
        #expect(abs(Double(hundredth) - 100 * odd.samplesPerBeat) < 1)
        #expect(odd.beat(atSample: hundredth, start: 0).rounded() == 100)
    }

    @Test func tapTempoAveragesRecentTaps() {
        #expect(ClickSchedule.bpm(fromTaps: [0, 0.5, 1.0, 1.5]) == 120)
        #expect(ClickSchedule.bpm(fromTaps: [0]) == nil)
        // A pause is ignored, not averaged in.
        #expect(ClickSchedule.bpm(fromTaps: [0, 5, 5.5, 6.0]) == 120)
    }
}

struct ChordLibraryTests {
    @Test func everyVoicingIsWellFormedAndUnique() {
        let names = ChordLibrary.voicings.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(ChordLibrary.voicings.count >= 40)
        for voicing in ChordLibrary.voicings {
            #expect(voicing.frets.count == 6, Comment(rawValue: voicing.name))
            #expect(voicing.fingers?.count == 6, Comment(rawValue: voicing.name))
            #expect(voicing.frets.compactMap { $0 }.allSatisfy { (0...12).contains($0) }, Comment(rawValue: voicing.name))
            #expect(voicing.pitches().count >= 2, Comment(rawValue: voicing.name))
        }
    }

    /// The notes actually fretted must spell the chord the name says, via MusicTheoryKit.
    @Test(arguments: ["C", "G", "D", "A", "E", "Am", "Em", "Dm", "F", "E7", "A7", "G7", "B7", "Am7", "Cmaj7", "F♯m", "B♭", "Bm", "G (barre)", "C♯m"])
    func voicingsSoundTheirChord(name: String) throws {
        let voicing = try #require(ChordLibrary.voicing(named: name))
        let chord = try #require(ChordAnalysis.chord(pitches: voicing.pitches()))
        let expected = name.replacingOccurrences(of: " (barre)", with: "")
        #expect(chord.name(sharps: expected.contains("♭") ? -1 : 1) == expected, "\(name) read as \(chord.name(sharps: 1))")
    }

    @Test func baseFretMovesUpTheNeckForBarres() {
        #expect(ChordLibrary.voicing(named: "C")?.baseFret == 1)
        #expect(ChordLibrary.voicing(named: "B (barre)")?.baseFret == 7)
    }

    @Test func changeKeysAreUnordered() {
        let c = ChordLibrary.voicing(named: "C")!, g = ChordLibrary.voicing(named: "G")!
        #expect(ChordVoicing.changeKey(c, g) == "change:C>G")
        #expect(ChordVoicing.changeKey(g, c) == "change:C>G")
        #expect(ChordChangeDrill.pair(fromKey: "change:C>G")! == ("C", "G"))
    }
}

struct ChordChangeDrillTests {
    @Test func changesPerMinute() {
        #expect(ChordChangeDrill.Result(changes: 30, seconds: 60).changesPerMinute == 30)
        #expect(ChordChangeDrill.Result(changes: 10, seconds: 30).changesPerMinute == 20)
    }

    @Test func weakestPairHasTheLowestBest() {
        let weakest = ChordChangeDrill.weakestPair(bests: ["change:C>G": 40, "change:Am>F": 12, "change:D>G": 30])
        #expect(weakest! == ("Am", "F"))
        #expect(ChordChangeDrill.weakestPair(bests: [:]) == nil)
    }

    @Test func qualityComparesWithTheBest() {
        #expect(ChordChangeDrill.quality(changesPerMinute: 20, best: nil) == 4)
        #expect(ChordChangeDrill.quality(changesPerMinute: 35, best: 30) == 5)
        #expect(ChordChangeDrill.quality(changesPerMinute: 26, best: 30) == 4)
        #expect(ChordChangeDrill.quality(changesPerMinute: 10, best: 30) == 3)
    }

    @Test func routineIncludesAChordChangeBlock() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 10, learnedFretCards: 30, chordBests: ["change:Am>F": 12, "change:C>G": 40]))
        let change = routine.first { $0.kind == .chordChange }
        #expect(change?.title == "Am → F")
        #expect(change?.minutes == 2)
        #expect(RoutineBuilder.totalMinutes(routine) == 20)
        #expect(RoutineBuilder.routine(.init(goalMinutes: 20, dueFretCards: 0, learnedFretCards: 0)).first { $0.kind == .chordChange }?.title == "C → G")
    }
}
