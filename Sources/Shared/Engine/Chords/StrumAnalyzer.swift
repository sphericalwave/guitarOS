import Accelerate
import Foundation
import PitchKit

/// Hears strums for the chord drill: raw input samples in, one `Strum` per onset out, saying which of the
/// notes it was told to listen for were ringing just after the pick.
///
/// Score-informed: the drill knows which voicings are in play, and their notes go to PitchKit's template
/// estimator as the expected prior, which lowers their bar and raises everyone else's. Frames 100–250 ms after
/// the onset are judged: past the pick noise, before the decay. A note counts as present when the estimator
/// finds it in two of those frames, or when its own fundamental stands as a spectral peak in most of them with
/// real overtone energy behind it (the greedy estimator can drop a chord tone whose overtones a lower string
/// already claimed). The frets either side of each expected note are checked the same way, so a wrong fret
/// shows up. A candidate with some overtone energy but never found is weak.
/// Pure and synchronous: feed it samples from one thread at a time.
nonisolated final class StrumAnalyzer {
    struct Strum: Equatable, Sendable {
        /// When the pick hit, in the caller's clock (the time of the first sample given, plus offset).
        var time: TimeInterval
        /// Candidates that rang.
        var present: Set<UInt8>
        /// Candidates that were there but faint: a muted or buzzing string.
        var weak: Set<UInt8>
    }

    /// Frames whose window ends this long after the onset are judged.
    static let judgeFrom: TimeInterval = 0.1
    static let judgeUntil: TimeInterval = 0.25
    /// A second onset this soon after the first is the same strum's later strings.
    static let strumSpan: TimeInterval = 0.15
    /// Faint presence, as a share of the bar.
    static let weakShare: Float = 0.4
    /// Overtone energy a note with a fundamental peak needs, as a share of the bar.
    static let peakShare: Float = 0.5
    /// A fundamental peak must be at least this share of the loudest bin within ±8 bins, or it's a sidelobe.
    static let sidelobeShare: Float = 0.05

    let sampleRate: Double
    let profile: InstrumentProfile
    let windowLength: Int
    let hopLength: Int

    /// Notes to listen for: the voicings in play.
    var candidates: Set<UInt8> = [] {
        didSet { scored = Self.scoredNotes(candidates, range: profile.range) }
    }
    /// 0...1 as in PitchKit: higher finds quieter notes.
    var sensitivity: Double {
        get { estimator.sensitivity }
        set { estimator.sensitivity = newValue; onsets.sensitivity = newValue }
    }

    /// Candidates and their neighbouring frets.
    private var scored: Set<UInt8> = []
    private let analyzer: SpectrumAnalyzer
    private var estimator: PolyphonicNoteEstimator
    private var onsets: OnsetDetector
    private let fluxBins: Range<Int>
    private let noiseBins: Range<Int>
    private let fundamentalBins: Range<Int>
    private var buffer: [Float] = []
    /// Time of sample 0 of `buffer`.
    private var bufferStart: TimeInterval = 0
    /// Where the next window ends in `buffer`.
    private var nextEnd: Int
    private var pending: Pending?

    private struct Pending {
        var onsetTime: TimeInterval
        /// Frames the estimator found each note in.
        var hits: [UInt8: Int] = [:]
        /// Frames with a spectral peak at each scored note's fundamental.
        var peakHits: [UInt8: Int] = [:]
        /// Candidates with some overtone energy, as a share of their bar.
        var share: [UInt8: Float] = [:]
        var frames = 0
    }

    init(sampleRate: Double, profile: InstrumentProfile, sensitivity: Double = 0.5) {
        self.sampleRate = sampleRate
        self.profile = profile
        // Twice the detector's window: strums need bass resolution more than they need speed.
        windowLength = (sampleRate > 60_000 ? profile.windowLength * 2 : profile.windowLength) * 2
        hopLength = windowLength / 8
        nextEnd = windowLength
        let fftSize = windowLength * 2
        analyzer = SpectrumAnalyzer(windowLength: windowLength, fftSize: fftSize)
        estimator = PolyphonicNoteEstimator(sampleRate: sampleRate, fftSize: fftSize, profile: profile)
        estimator.sensitivity = sensitivity
        // Flux is compared one 21 ms step back, as in the detector.
        onsets = OnsetDetector(framesPerStep: max(1, Int((0.021 * sampleRate / Double(hopLength)).rounded())), sensitivity: sensitivity)
        let bin = { [analyzer] (frequency: Double) in Int(analyzer.bin(of: frequency, sampleRate: sampleRate)) }
        fluxBins = bin(60)..<bin(min(6000, sampleRate * 0.45))
        noiseBins = bin(50)..<bin(min(5000, sampleRate * 0.45))
        fundamentalBins = max(2, bin(profile.minFrequency))..<min(bin(profile.maxFrequency), fftSize / 2 - 2)
    }

    /// Feeds samples that began at `startTime`. Strums judged within them come back.
    func process(_ samples: UnsafeBufferPointer<Float>, startTime: TimeInterval) -> [Strum] {
        if buffer.isEmpty { bufferStart = startTime }
        buffer.append(contentsOf: samples)
        var strums: [Strum] = []
        while nextEnd <= buffer.count {
            if let strum = analyze(windowEnding: nextEnd) { strums.append(strum) }
            nextEnd += hopLength
        }
        // Drop what every future window has moved past, now and then rather than every call.
        let consumed = nextEnd - windowLength
        if consumed > windowLength * 4 {
            buffer.removeFirst(consumed)
            nextEnd -= consumed
            bufferStart += Double(consumed) / sampleRate
        }
        return strums
    }

    func reset() {
        buffer = []
        nextEnd = windowLength
        pending = nil
        onsets.reset()
    }

    // MARK: Private

    private func analyze(windowEnding end: Int) -> Strum? {
        let window = buffer[(end - windowLength)..<end]
        let magnitudes = analyzer.magnitudes(of: window)
        let loud = NoteDetector.decibels(rms: vDSP.rootMeanSquare(window)) > profile.gateDecibels
        let isOnset = onsets.process(magnitudes, bins: fluxBins) && loud
        let endTime = bufferStart + Double(end) / sampleRate
        var finished: Strum?

        if isOnset {
            // The strike sits about a hop before this window's end once the flux sees it.
            let onsetTime = endTime - Double(hopLength) / sampleRate
            if let open = pending {
                if onsetTime - open.onsetTime >= Self.strumSpan {
                    // A new strum: judge the old one with what it has.
                    finished = judge(open)
                    pending = Pending(onsetTime: onsetTime)
                } else if open.frames == 0 {
                    // A blip just before the strings rang (a finger lifting, the pick touching): the strum starts here.
                    pending = Pending(onsetTime: onsetTime)
                }
            } else {
                pending = Pending(onsetTime: onsetTime)
            }
        }

        guard var open = pending, finished == nil else { return finished }
        let since = endTime - open.onsetTime
        if since >= Self.judgeFrom, since <= Self.judgeUntil, !candidates.isEmpty {
            let noise = Self.noiseFloor(magnitudes, bins: noiseBins)
            for detection in estimator.estimate(magnitudes, noiseFloor: noise, prior: .init(expected: candidates)) {
                open.hits[detection.note, default: 0] += 1
            }
            for note in fundamentalPeaks(in: magnitudes, noise: noise) {
                open.peakHits[note, default: 0] += 1
            }
            for note in scored {
                let share = estimator.salience(of: note, in: magnitudes) / estimator.threshold(of: note, noiseFloor: noise)
                open.share[note] = max(open.share[note, default: 0], share)
            }
            open.frames += 1
        }
        if since > Self.judgeUntil {
            pending = nil
            return judge(open)
        }
        pending = open
        return nil
    }

    private func judge(_ pending: Pending) -> Strum {
        let needed = pending.frames >= 4 ? 2 : 1
        var present = Set(pending.hits.filter { $0.value >= needed }.keys)
        for (note, frames) in pending.peakHits where frames * 2 >= pending.frames && pending.share[note, default: 0] >= Self.peakShare {
            present.insert(note)
        }
        // A neighbouring fret whose "fundamental" is an overtone of a chord tone that rang is that overtone.
        let chordTones = present.intersection(candidates)
        for note in present where !candidates.contains(note) {
            let frequency = profile.frequency(of: Int(note))
            let isOvertone = chordTones.contains { tone in
                tone < note && (2...8).contains { abs(PitchMath.cents(from: profile.partial($0, of: Int(tone)), to: frequency)) <= PolyphonicNoteEstimator.toleranceCents }
            }
            if isOvertone { present.remove(note) }
        }
        let weak = Set(pending.share.filter { candidates.contains($0.key) && !present.contains($0.key) && $0.value >= Self.weakShare }.keys)
        return Strum(time: pending.onsetTime, present: present, weak: weak)
    }

    /// Scored notes whose fundamental is a peak of its own in this frame, by the peak's interpolated frequency.
    private func fundamentalPeaks(in magnitudes: [Float], noise: Float) -> Set<UInt8> {
        let peaks = PolyphonicNoteEstimator.peaks(of: magnitudes)
        let floor = max(noise * 4, (peaks.max() ?? 0) * 0.003)
        var notes: Set<UInt8> = []
        for bin in fundamentalBins where peaks[bin] > floor {
            // The Hann window's sidelobes (−31 dB and below, a few bins out) are local maxima too: a peak has
            // to stand within 26 dB of everything near it.
            let around = magnitudes[max(0, bin - 8)...min(magnitudes.count - 1, bin + 8)].max() ?? 0
            guard peaks[bin] >= around * Self.sidelobeShare else { continue }
            // Parabolic interpolation on log magnitudes puts the peak between bins.
            let a = log(max(magnitudes[bin - 1], 1e-9)), b = log(max(magnitudes[bin], 1e-9)), c = log(max(magnitudes[bin + 1], 1e-9))
            let denominator = a - 2 * b + c
            let delta = denominator < 0 ? 0.5 * (a - c) / denominator : 0
            let frequency = analyzer.frequency(ofBin: Double(bin) + Double(delta), sampleRate: sampleRate)
            let nearest = PitchMath.note(nearest: frequency, a4: profile.a4)
            guard abs(nearest.cents) <= PolyphonicNoteEstimator.toleranceCents, let note = UInt8(exactly: nearest.note), scored.contains(note) else { continue }
            notes.insert(note)
        }
        return notes
    }

    /// Candidates plus the fret either side of each, within the profile's range.
    private static func scoredNotes(_ candidates: Set<UInt8>, range: ClosedRange<UInt8>) -> Set<UInt8> {
        var notes = candidates
        for note in candidates {
            for offset in [-2, -1, 1, 2] {
                if let value = UInt8(exactly: Int(note) + offset), range.contains(value) { notes.insert(value) }
            }
        }
        return notes
    }

    /// The median bin is noise even while a chord plays: overtones are sparse.
    private static func noiseFloor(_ magnitudes: [Float], bins: Range<Int>) -> Float {
        var band = Array(magnitudes[bins])
        guard !band.isEmpty else { return 1e-5 }
        vDSP.sort(&band, sortOrder: .ascending)
        return max(band[band.count / 2], 1e-7)
    }
}
