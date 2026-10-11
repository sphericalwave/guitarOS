import Foundation
import PitchKit
@testable import guitar

/// Karplus–Strong plucked strings for tests: a noise burst through a short delay line with a
/// one-pole low-pass, which is a surprisingly good guitar. Deterministic.
nonisolated struct GuitarToneSynth {
    struct Pluck {
        var frequency: Double
        var start: TimeInterval
        var amplitude: Float = 0.3
        /// 0...1: higher keeps the string ringing longer and brighter.
        var sustain: Double = 0.996
        /// When the hand lifts off or palm-mutes: the string dies within ~30 ms of this.
        var release: TimeInterval?
    }

    var sampleRate: Double = 48_000
    var seed: UInt64 = 7
    /// Background noise RMS, relative to full scale.
    var noise: Float = 0.0003
    /// String stiffness: an all-pass in the loop stretches the overtones sharp, as on a real string. 0 is a
    /// perfectly harmonic string; ~0.1 is a wound string's slight stretch, 0.3 is exaggerated.
    var inharmonicity: Double = 0

    func render(_ plucks: [Pluck], duration: TimeInterval) -> [Float] {
        var output = [Float](repeating: 0, count: Int(duration * sampleRate))
        var random = SplitMix(state: seed)
        for pluck in plucks { add(pluck, to: &output, random: &random) }
        for index in output.indices {
            output[index] += (Float(random.nextUnit()) - 0.5) * noise * 3.46
        }
        return output
    }

    /// Strum: the same plucks spread a few milliseconds apart, low string first.
    static func strum(_ frequencies: [Double], at start: TimeInterval, spacing: TimeInterval = 0.012) -> [Pluck] {
        frequencies.enumerated().map { Pluck(frequency: $1, start: start + Double($0) * spacing) }
    }

    /// A voicing strummed low string first. `muted` strings (1 = high E) give a dead thud instead of a note,
    /// as a finger that didn't press hard enough does; `release` damps every string at that time (the hand
    /// moving to the next chord).
    static func strum(_ voicing: ChordVoicing, tuning: Tuning = .standard, at start: TimeInterval, a4: Double = 440,
                      muted: Set<Int> = [], release: TimeInterval? = nil, spacing: TimeInterval = 0.012) -> [Pluck] {
        ChordVerifier.expectedStrings(voicing, tuning: tuning).enumerated().map { index, string in
            var pluck = Pluck(frequency: PitchMath.frequency(of: Int(string.pitch), a4: a4), start: start + Double(index) * spacing, release: release)
            if muted.contains(string.string) {
                // A finger resting on the string: a thud that dies within a few periods.
                pluck.amplitude = 0.1
                pluck.sustain = 0.6
            }
            return pluck
        }
    }

    private func add(_ pluck: Pluck, to output: inout [Float], random: inout SplitMix) {
        // Loop delay must equal the period: N + f from the line (N whole samples plus a linear
        // interpolation fraction f), 0.5 from the two-point loss filter, and the all-pass's low-frequency
        // delay (1 − c) / (1 + c) when the string is stiff.
        let c = Float(inharmonicity)
        let allpassDelay = inharmonicity > 0 ? (1 - inharmonicity) / (1 + inharmonicity) : 0
        let period = sampleRate / pluck.frequency - 0.5 - allpassDelay
        let whole = Int(period.rounded(.down))
        let fraction = Float(period - Double(whole))
        guard whole >= 2 else { return }
        // whole + 1 slots: slot `head` is the oldest sample (delay N+1), the one after it is delay N.
        let slots = whole + 1
        // A pick displaces the string into a triangle (strong, 1/k² harmonics, as a real pluck), plus noise
        // for the scrape. Pure noise would leave some strings with a weak fundamental by chance.
        let pluckPoint = Float(slots) * 0.23
        var line = (0..<slots).map { index -> Float in
            let x = Float(index)
            let triangle = x < pluckPoint ? x / pluckPoint : (Float(slots) - x) / (Float(slots) - pluckPoint)
            return (triangle * 2 - 1) * 0.7 + (Float(random.nextUnit()) * 2 - 1) * 0.3
        }
        let mean = line.reduce(0, +) / Float(line.count)
        for index in line.indices { line[index] -= mean }

        var head = 0
        var previous: Float = 0
        var allpassIn: Float = 0
        var allpassOut: Float = 0
        let first = max(0, Int(pluck.start * sampleRate))
        let releaseAt = pluck.release.map { max(first, Int($0 * sampleRate)) }
        for index in first..<output.count {
            let delayN = line[(head + 1) % slots]
            let delayN1 = line[head]
            let sample = delayN + (delayN1 - delayN) * fraction
            var sustain = Float(pluck.sustain)
            if let releaseAt, index >= releaseAt { sustain = 0.6 }
            var filtered = sustain * 0.5 * (sample + previous)
            previous = sample
            if inharmonicity > 0 {
                // First-order all-pass: y[n] = c·x[n] + x[n−1] − c·y[n−1]. Dispersion stretches the overtones.
                let y = c * filtered + allpassIn - c * allpassOut
                allpassIn = filtered
                allpassOut = y
                filtered = y
            }
            line[head] = filtered
            head = (head + 1) % slots
            output[index] += pluck.amplitude * sample
            if index > first + Int(sampleRate), abs(sample) < 1e-5 { break }
        }
    }
}

nonisolated struct SplitMix {
    var state: UInt64

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
