import Foundation
import MusicTheoryKit
import PitchKit

/// Pure tuner arithmetic: a frequency against a tuning and a reference A.
nonisolated enum TunerModel {
    struct Reading: Equatable, Sendable {
        var frequency: Double
        /// Guitarist's string number the reading is closest to (1 = high E).
        var string: Int
        /// MIDI pitch of that string's open note.
        var targetPitch: UInt8
        var targetFrequency: Double
        /// Positive is sharp. Relative to the target string, so can exceed ±50.
        var cents: Double

        var isInTune: Bool { abs(cents) <= TunerModel.inTuneCents }
        var noteName: String { PitchName.name(for: targetPitch) }
    }

    /// "In tune" band, as most clip-on tuners show it.
    static let inTuneCents = 3.0
    /// Frames of smoothing: the median of the last few readings steadies the needle.
    static let smoothingWindow = 5

    /// The open string whose pitch is nearest in log-frequency, and how far off the string is.
    static func reading(frequency: Double, tuning: Tuning, referenceA: Double) -> Reading {
        var best: Reading?
        for string in 1...tuning.stringCount {
            let pitch = tuning.openPitch(string: string)
            let target = PitchMath.frequency(of: Int(pitch), a4: referenceA)
            let cents = PitchMath.cents(from: target, to: frequency)
            if best == nil || abs(cents) < abs(best!.cents) {
                best = Reading(frequency: frequency, string: string, targetPitch: pitch, targetFrequency: target, cents: cents)
            }
        }
        return best!
    }

    /// Chromatic reading: nearest note to any pitch, for the "what note is this" readout.
    static func nearestNote(frequency: Double, referenceA: Double) -> (note: Int, cents: Double) {
        PitchMath.note(nearest: frequency, a4: referenceA)
    }

    /// Median of the most recent frequencies, so one bad hop doesn't jump the needle.
    static func smoothed(_ recent: [Double]) -> Double? {
        guard !recent.isEmpty else { return nil }
        let window = Array(recent.suffix(smoothingWindow)).sorted()
        return window[window.count / 2]
    }
}
