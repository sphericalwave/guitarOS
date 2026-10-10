import AVFoundation

/// The shared audio session's inputs. Plugging in a USB interface makes it the route automatically;
/// this lets the person switch back and forth.
struct PlatformAudioInputs: AudioInputSelecting {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    var availableInputs: [AudioInput] {
        (session.availableInputs ?? []).map(AudioInput.init)
    }

    var currentInput: AudioInput? {
        session.currentRoute.inputs.first.map(AudioInput.init)
    }

    func select(_ input: AudioInput) throws {
        guard let port = session.availableInputs?.first(where: { $0.uid == input.id }) else { return }
        try session.setPreferredInput(port)
    }

    var isSpeakerOutput: Bool {
        session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }
    }

    var canSelectInputs: Bool { true }
}

private extension AudioInput {
    init(_ port: AVAudioSessionPortDescription) {
        self.init(id: port.uid, name: port.portName, isExternal: port.portType != .builtInMic)
    }
}
