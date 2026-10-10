import Foundation

/// One input the system offers: the built-in mic, a USB interface, a headset.
nonisolated struct AudioInput: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var isExternal: Bool
}

/// Lists and selects audio inputs, and says whether sound would come out of the built-in speaker
/// (where input monitoring would feed back). iOS has an audio session for this; macOS leaves input
/// choice to System Settings.
protocol AudioInputSelecting: Sendable {
    var availableInputs: [AudioInput] { get }
    var currentInput: AudioInput? { get }
    func select(_ input: AudioInput) throws
    var isSpeakerOutput: Bool { get }
    /// Whether the platform lets the app pick inputs at all.
    var canSelectInputs: Bool { get }
}
