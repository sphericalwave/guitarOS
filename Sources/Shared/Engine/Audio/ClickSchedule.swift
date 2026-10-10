import Foundation

/// Where clicks fall in a sample stream. Pure, so the metronome's timing is unit-tested; `ClickTrack`
/// renders it. Beat 0 of every bar is accented.
nonisolated struct ClickSchedule: Equatable, Sendable {
    var bpm: Double
    var beatsPerBar: Int
    var sampleRate: Double

    var samplesPerBeat: Double { sampleRate * 60 / bpm }

    /// Sample position of beat `index` (0 = the first click), from a start sample.
    func sample(ofBeat index: Int, start: Int) -> Int {
        start + Int((Double(index) * samplesPerBeat).rounded())
    }

    /// Beats whose click starts within [from, to), with whether each is accented.
    func clicks(in range: Range<Int>, start: Int) -> [(sample: Int, beat: Int, isAccent: Bool)] {
        guard range.upperBound > start else { return [] }
        let first = max(0, Int((Double(range.lowerBound - start) / samplesPerBeat).rounded(.down)))
        var result: [(Int, Int, Bool)] = []
        var beat = first
        while true {
            let sample = self.sample(ofBeat: beat, start: start)
            if sample >= range.upperBound { break }
            if sample >= range.lowerBound { result.append((sample, beat, beatsPerBar > 0 && beat % beatsPerBar == 0)) }
            beat += 1
        }
        return result
    }

    /// Fractional beat position of a sample, for judging rhythm later.
    func beat(atSample sample: Int, start: Int) -> Double {
        Double(sample - start) / samplesPerBeat
    }

    /// BPM from tap intervals: the mean of the last few taps, ignoring a long pause.
    static func bpm(fromTaps taps: [TimeInterval]) -> Double? {
        let recent = Array(taps.suffix(5))
        guard recent.count >= 2 else { return nil }
        let intervals = zip(recent.dropFirst(), recent).map { $0 - $1 }.filter { $0 > 0.2 && $0 < 2.5 }
        guard !intervals.isEmpty else { return nil }
        return (60 / (intervals.reduce(0, +) / Double(intervals.count))).rounded()
    }

    static let bpmRange = 30.0...300.0
}
