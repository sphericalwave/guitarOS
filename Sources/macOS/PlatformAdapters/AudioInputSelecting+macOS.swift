import Foundation

/// macOS records from the system's default input, chosen in System Settings › Sound. The output route
/// isn't known here, so monitoring stays off (an interface monitors on its own anyway).
struct PlatformAudioInputs: AudioInputSelecting {
    var availableInputs: [AudioInput] { [] }
    var currentInput: AudioInput? { AudioInput(id: "system", name: "System input", isExternal: false) }
    func select(_ input: AudioInput) throws {}
    var isSpeakerOutput: Bool { true }
    var canSelectInputs: Bool { false }
}
