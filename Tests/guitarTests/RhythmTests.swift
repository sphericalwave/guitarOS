import Foundation
import Testing
import PitchKit
@testable import guitar

struct RhythmJudgeTests {
    /// 120 BPM, eighths, beats 4...12 (two bars after a one-bar count-in). A beat is 500 ms.
    private func judge() -> RhythmJudge { RhythmJudge(bpm: 120, subdivision: .eighths, range: 4...12) }

    @Test func strikesMeasureToTheNearestGridPointInMilliseconds() {
        var judge = judge()
        let onTime = judge.strike(atBeat: 4.02)       // 10 ms late
        #expect(onTime?.target == 4 && abs(onTime!.offset - 10) < 1e-9 && onTime!.isOnTime)
        let early = judge.strike(atBeat: 4.44)        // the "and" of 4, 30 ms early
        #expect(early?.target == 4.5 && abs(early!.offset + 30) < 1e-9 && early!.isOnTime)
        let late = judge.strike(atBeat: 5.12)         // 60 ms late: counted, not on time
        #expect(late?.target == 5 && !late!.isOnTime)
        #expect(judge.strikes.count == 3)
    }

    @Test func straysAndStrikesOutsideThePassAreIgnored() {
        var judge = judge()
        #expect(judge.strike(atBeat: 4.25) == nil, "halfway between eighths")
        #expect(judge.strike(atBeat: 2.0) == nil, "during the count-in")
        #expect(judge.strike(atBeat: 13.0) == nil, "after the pass")
        #expect(judge.strikes.isEmpty)
    }

    @Test func summaryCountsMissesAndFindsTheTendency() {
        var judge = judge()
        // Hit every eighth from 4 to 12 (17 points), all 20 ms late, except skip beat 8.
        var point = 4.0
        while point <= 12 {
            if point != 8 { judge.strike(atBeat: point + 0.04) }
            point += 0.5
        }
        let summary = judge.summary
        #expect(summary.strikes == 16 && summary.onTime == 16 && summary.missed == 1)
        #expect(abs(summary.meanOffset - 20) < 1e-9 && summary.standardDeviation < 1e-9)
        #expect(summary.tendency == "Dragging by 20 ms")
        #expect(abs(summary.accuracy - 16.0 / 17) < 1e-9)
        #expect(RhythmJudge.quality(summary) == 5)
        judge.reset()
        #expect(judge.summary.missed == 17 && RhythmJudge.quality(judge.summary) == 1)
    }

    @Test func tripletsUseAThirdOfABeat() {
        var judge = RhythmJudge(bpm: 90, subdivision: .triplets, range: 0...1)
        #expect(judge.strike(atBeat: 1.0 / 3 + 0.01)?.target == 1.0 / 3)
        #expect(abs(judge.strike(atBeat: 2.0 / 3)!.offset) < 1e-9)
        #expect(judge.summary.missed == 2, "0 and 1 weren't hit")
    }
}

struct OnsetAnalyzerTests {
    @Test func hearsEachPluckOnceWithinAFewMilliseconds() {
        let synth = GuitarToneSynth()
        let starts = [0.2, 0.7, 1.2, 1.7]
        let samples = synth.render(starts.map { .init(frequency: PitchMath.frequency(of: 52), start: $0) }, duration: 2.3)
        let analyzer = OnsetAnalyzer(sampleRate: synth.sampleRate, gateDecibels: -75, sensitivity: 0.7)
        var heard: [TimeInterval] = []
        var index = 0
        while index < samples.count {
            let end = min(index + 512, samples.count)
            heard += samples[index..<end].withUnsafeBufferPointer { analyzer.process($0, startTime: Double(index) / synth.sampleRate) }
            index = end
        }
        #expect(heard.count == 4, "\(heard)")
        for (start, time) in zip(starts, heard) { #expect(abs(time - start) < 0.02, "\(start) heard at \(time)") }
    }
}

struct ClickTrackJudgingTests {
    @Test func routineAddsARhythmBlockOnLongerDays() {
        let routine = RoutineBuilder.routine(.init(goalMinutes: 25, dueFretCards: 0, learnedFretCards: 30))
        #expect(routine.map(\.kind) == [.tuner, .chordChange, .scale, .rhythm, .free])
        #expect(routine.first { $0.kind == .rhythm }?.minutes == 2)
        #expect(RoutineBuilder.totalMinutes(routine) == 25)
    }
}
