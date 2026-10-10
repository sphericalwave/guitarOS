import Foundation
import PitchKit

/// How the guitar reaches the microphone. An unplugged electric is 20–30 dB quieter than an acoustic,
/// so it needs a lower silence gate and more sensitivity; a USB interface gives a clean, hot signal.
nonisolated enum InputProfile: String, CaseIterable, Identifiable, Sendable {
    case unpluggedElectric
    case di

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unpluggedElectric: "Built-in mic"
        case .di: "USB interface"
        }
    }

    var hint: String {
        switch self {
        case .unpluggedElectric: "Keep the device within an arm's length of the strings."
        case .di: "Clean signal, no speaker bleed. Turn on monitoring to hear yourself through headphones."
        }
    }

    var defaultSensitivity: Double {
        switch self {
        case .unpluggedElectric: 0.7
        case .di: 0.5
        }
    }

    var gateDecibels: Float {
        switch self {
        case .unpluggedElectric: -75
        case .di: -60
        }
    }

    func detectorProfile(referenceA: Double) -> InstrumentProfile {
        .guitar(a4: referenceA, gateDecibels: gateDecibels)
    }
}

/// The reference pitch everything is judged against. A guitar tuned to A432 sits ~32 cents flat of A440,
/// so the choice has to reach the detector, the tuner and every drill, not just the tuner display.
nonisolated enum ReferencePitch {
    static let standard = 440.0
    static let alternate = 432.0
    static let customRange = 415.0...466.0

    static func clamped(_ value: Double) -> Double {
        min(max(value, customRange.lowerBound), customRange.upperBound)
    }
}
