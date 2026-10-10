import Foundation

/// Turns an auto-graded attempt into an SM-2 quality (0–5). Wrong is 1; right gets better with speed.
/// Thresholds are per kind: finding a fret is quick, a chord change isn't.
nonisolated enum AutoGrade {
    struct Thresholds: Sendable, Equatable {
        /// Faster than this is "easy" (5).
        var fast: TimeInterval
        /// Slower than this is "hard" (3); between is "good" (4).
        var slow: TimeInterval

        static let fretPosition = Thresholds(fast: 2, slow: 5)
        static let nameTheNote = Thresholds(fast: 1.5, slow: 4)
    }

    static func quality(correct: Bool, response: TimeInterval, thresholds: Thresholds = .fretPosition) -> Int {
        guard correct else { return 1 }
        if response < thresholds.fast { return 5 }
        if response < thresholds.slow { return 4 }
        return 3
    }

    /// Rolling mean that weights the newest answer at 1/n, capped so old habits still fade.
    static func updatedMean(_ mean: Double, with response: TimeInterval, count: Int) -> Double {
        let n = Double(min(max(count, 1), 10))
        return mean + (response - mean) / n
    }
}
