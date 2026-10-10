import Foundation

/// Karplus–Strong plucked strings for tests: a noise burst through a short delay line with a
/// one-pole low-pass, which is a surprisingly good guitar. Deterministic.
nonisolated struct GuitarToneSynth {
    struct Pluck {
        var frequency: Double
        var start: TimeInterval
        var amplitude: Float = 0.3
        /// 0...1: higher keeps the string ringing longer and brighter.
        var sustain: Double = 0.996
    }

    var sampleRate: Double = 48_000
    var seed: UInt64 = 7
    /// Background noise RMS, relative to full scale.
    var noise: Float = 0.0003

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

    private func add(_ pluck: Pluck, to output: inout [Float], random: inout SplitMix) {
        // Loop delay must equal the period: N + f from the line (N whole samples plus a linear
        // interpolation fraction f) and 0.5 from the two-point loss filter.
        let period = sampleRate / pluck.frequency - 0.5
        let whole = Int(period.rounded(.down))
        let fraction = Float(period - Double(whole))
        guard whole >= 2 else { return }
        // whole + 1 slots: slot `head` is the oldest sample (delay N+1), the one after it is delay N.
        let slots = whole + 1
        var line = (0..<slots).map { _ in Float(random.nextUnit()) * 2 - 1 }
        let mean = line.reduce(0, +) / Float(line.count)
        for index in line.indices { line[index] -= mean }

        var head = 0
        var previous: Float = 0
        let first = max(0, Int(pluck.start * sampleRate))
        for index in first..<output.count {
            let delayN = line[(head + 1) % slots]
            let delayN1 = line[head]
            let sample = delayN + (delayN1 - delayN) * fraction
            let filtered = Float(pluck.sustain) * 0.5 * (sample + previous)
            previous = sample
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
