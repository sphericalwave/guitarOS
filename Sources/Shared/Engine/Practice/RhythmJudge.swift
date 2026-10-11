import Accelerate
import Foundation
import PitchKit

/// Judges strikes against the click: each onset is measured to the nearest grid point of the chosen
/// subdivision, in milliseconds (early negative), and the pass is summed up as how many landed within the
/// window, the mean (rushing or dragging) and the spread.
nonisolated struct RhythmJudge: Equatable, Sendable {
    enum Subdivision: Int, CaseIterable, Identifiable, Sendable {
        case quarters = 1, eighths = 2, triplets = 3, sixteenths = 4

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .quarters: "Quarters"
            case .eighths: "Eighths"
            case .triplets: "Triplets"
            case .sixteenths: "Sixteenths"
            }
        }
        /// Card key fragment.
        var key: String {
            switch self {
            case .quarters: "quarters"
            case .eighths: "eighths"
            case .triplets: "triplets"
            case .sixteenths: "sixteenths"
            }
        }
    }

    struct Strike: Equatable, Sendable, Identifiable {
        var id: Int
        /// Fractional beat where it landed.
        var beat: Double
        /// Grid point it was measured against (in beats).
        var target: Double
        /// Milliseconds from the grid point; early is negative.
        var offset: Double
        var isOnTime: Bool
    }

    struct Summary: Equatable, Sendable {
        var strikes = 0
        var onTime = 0
        /// Grid points in the judged span with no strike near them.
        var missed = 0
        var meanOffset: Double = 0
        var standardDeviation: Double = 0

        var accuracy: Double { strikes + missed == 0 ? 0 : Double(onTime) / Double(strikes + missed) }
        /// "Rushing" when the mean is clearly early, "dragging" when late.
        var tendency: String {
            if abs(meanOffset) < 10 { return "Right on the beat" }
            return meanOffset < 0 ? "Rushing by \(Int(-meanOffset.rounded())) ms" : "Dragging by \(Int(meanOffset.rounded())) ms"
        }
    }

    /// A strike this close to a grid point is on time.
    static let onTimeWindow: Double = 40
    /// Farther than this from any grid point and it's a stray, not judged.
    static let strayWindow: Double = 0.45

    let bpm: Double
    let subdivision: Subdivision
    /// Beats the pass covers, after the count-in: strikes outside aren't judged.
    let range: ClosedRange<Double>
    private(set) var strikes: [Strike] = []
    private var nextID = 0

    init(bpm: Double, subdivision: Subdivision, range: ClosedRange<Double>) {
        self.bpm = bpm
        self.subdivision = subdivision
        self.range = range
    }

    var millisecondsPerBeat: Double { 60_000 / bpm }

    /// Records a strike at a fractional beat. Returns it when it counts; nil for strays and strikes outside the pass.
    @discardableResult
    mutating func strike(atBeat beat: Double) -> Strike? {
        let step = 1 / Double(subdivision.rawValue)
        guard beat >= range.lowerBound - step / 2, beat <= range.upperBound + step / 2 else { return nil }
        let target = (beat / step).rounded() * step
        let offsetBeats = beat - target
        guard abs(offsetBeats) <= Self.strayWindow * step else { return nil }
        let offset = offsetBeats * millisecondsPerBeat
        let strike = Strike(id: nextID, beat: beat, target: target, offset: offset, isOnTime: abs(offset) <= Self.onTimeWindow)
        nextID += 1
        strikes.append(strike)
        return strike
    }

    /// The pass so far: counts, tendency and spread, with grid points nobody hit counted as missed.
    var summary: Summary {
        var summary = Summary()
        summary.strikes = strikes.count
        summary.onTime = strikes.filter(\.isOnTime).count
        let step = 1 / Double(subdivision.rawValue)
        let hitTargets = Set(strikes.map { Int(($0.target / step).rounded()) })
        var point = range.lowerBound
        var expected = 0
        while point <= range.upperBound + 1e-9 {
            expected += 1
            if !hitTargets.contains(Int((point / step).rounded())) { summary.missed += 1 }
            point += step
        }
        guard !strikes.isEmpty else { return summary }
        let offsets = strikes.map(\.offset)
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        summary.meanOffset = mean
        summary.standardDeviation = (offsets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(offsets.count)).squareRoot()
        return summary
    }

    mutating func reset() {
        strikes = []
        nextID = 0
    }

    /// SM-2 quality: on-time share with the spread as a tie-breaker.
    static func quality(_ summary: Summary) -> Int {
        if summary.accuracy >= 0.9 && summary.standardDeviation <= 20 { return 5 }
        if summary.accuracy >= 0.75 { return 4 }
        if summary.accuracy >= 0.5 { return 3 }
        return 1
    }
}

/// Finds when the player strikes a string: spectral-flux onsets on the raw input, reported at once with
/// their host-clock time. Pure and synchronous: feed it buffers from one thread at a time.
nonisolated final class OnsetAnalyzer {
    let sampleRate: Double
    let windowLength: Int
    let hopLength: Int
    /// Below this RMS (dBFS) a frame can't hold a strike.
    var gateDecibels: Float
    var sensitivity: Double {
        get { onsets.sensitivity }
        set { onsets.sensitivity = newValue }
    }

    private let analyzer: SpectrumAnalyzer
    private var onsets: OnsetDetector
    private let fluxBins: Range<Int>
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var nextEnd: Int

    init(sampleRate: Double, gateDecibels: Float, sensitivity: Double = 0.5) {
        self.sampleRate = sampleRate
        self.gateDecibels = gateDecibels
        windowLength = sampleRate > 60_000 ? 2048 : 1024
        hopLength = windowLength / 4
        nextEnd = windowLength
        analyzer = SpectrumAnalyzer(windowLength: windowLength, fftSize: windowLength * 2)
        onsets = OnsetDetector(framesPerStep: max(1, Int((0.021 * sampleRate / Double(hopLength)).rounded())), sensitivity: sensitivity)
        let bin = { [analyzer] (frequency: Double) in Int(analyzer.bin(of: frequency, sampleRate: sampleRate)) }
        fluxBins = bin(60)..<bin(min(8000, sampleRate * 0.45))
    }

    /// Feeds samples that began at `startTime`; returns the host-clock times of strikes heard in them.
    func process(_ samples: UnsafeBufferPointer<Float>, startTime: TimeInterval) -> [TimeInterval] {
        if buffer.isEmpty { bufferStart = startTime }
        buffer.append(contentsOf: samples)
        var times: [TimeInterval] = []
        while nextEnd <= buffer.count {
            let window = buffer[(nextEnd - windowLength)..<nextEnd]
            let magnitudes = analyzer.magnitudes(of: window)
            let loud = NoteDetector.decibels(rms: vDSP.rootMeanSquare(window)) > gateDecibels
            if onsets.process(magnitudes, bins: fluxBins), loud {
                // The strike sits about a hop before the end of the window that first shows it.
                times.append(bufferStart + Double(nextEnd - hopLength) / sampleRate)
            }
            nextEnd += hopLength
        }
        let consumed = nextEnd - windowLength
        if consumed > windowLength * 4 {
            buffer.removeFirst(consumed)
            nextEnd -= consumed
            bufferStart += Double(consumed) / sampleRate
        }
        return times
    }

    func reset() {
        buffer = []
        nextEnd = windowLength
        onsets.reset()
    }
}
