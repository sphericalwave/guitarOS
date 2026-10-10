import AVFoundation
import Observation
import DiagnosticsKit
import PitchKit

/// The one audio engine. Every screen that listens acquires it; it runs while at least one does.
/// Publishes level, the current pitch (for the tuner) and note events (for drills).
@Observable
@MainActor
final class AudioHub {
    enum Status: Equatable {
        case off
        case starting
        case listening
        /// Microphone access was refused (or is restricted on this device).
        case denied
        case unavailable(String)
    }

    private(set) var status: Status = .off
    /// Input loudness for a meter, 0...1 over −70...0 dBFS.
    private(set) var level: Double = 0
    private(set) var levelDecibels: Float = -120
    /// Latest single-note pitch, nil when nothing periodic is sounding.
    private(set) var pitch: PitchEstimate?
    /// Notes being heard right now.
    private(set) var heardPitches: Set<UInt8> = []
    /// Strike-to-note-on delay; judging subtracts it.
    private(set) var latency: TimeInterval = 0
    private(set) var inputs: [AudioInput] = []
    private(set) var currentInput: AudioInput?
    /// True when the output is the built-in speaker, where monitoring would feed back.
    private(set) var isSpeakerOutput = true

    /// The guitar's settings. Changing any of them rebuilds the detector.
    var referenceA: Double { didSet { if referenceA != oldValue { rebuildIfListening() } } }
    var inputProfile: InputProfile { didSet { if inputProfile != oldValue { rebuildIfListening() } } }
    var sensitivity: Double { didSet { capture?.setSensitivity(sensitivity) } }
    var monitorInput: Bool { didSet { if monitorInput != oldValue { rebuildIfListening() } } }

    /// Every note on and off heard.
    @ObservationIgnored var onEvent: ((NoteEvent) -> Void)?
    /// Asked as audio comes in for what the drill expects and what the app itself is playing.
    @ObservationIgnored var priorProvider: (() -> PolyphonicNoteEstimator.Prior)?

    var privacySettingsURL: URL? { session.privacySettingsURL }
    var canSelectInputs: Bool { inputSelector.canSelectInputs }
    /// Monitoring is only safe into headphones or an interface.
    var canMonitorInput: Bool { !isSpeakerOutput }

    @ObservationIgnored private let session: AudioRecordingSession
    @ObservationIgnored private let inputSelector: AudioInputSelecting
    @ObservationIgnored private var capture: MicrophoneCapture?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var capturedSince = Date.distantPast

    init(session: AudioRecordingSession, inputs: AudioInputSelecting,
         referenceA: Double = ReferencePitch.standard, inputProfile: InputProfile = .unpluggedElectric,
         sensitivity: Double? = nil, monitorInput: Bool = false) {
        self.session = session
        self.inputSelector = inputs
        self.referenceA = referenceA
        self.inputProfile = inputProfile
        self.sensitivity = sensitivity ?? inputProfile.defaultSensitivity
        self.monitorInput = monitorInput
    }

    /// Start listening if nobody was; pair each call with `release()`.
    func acquire() {
        users += 1
        guard users == 1 else { return }
        Task { await start() }
    }

    func release() {
        guard users > 0 else { return }
        users -= 1
        if users == 0 { stop() }
    }

    /// Try again after the person changed something (granted access, plugged in an interface).
    func retry() {
        guard users > 0, status != .listening, status != .starting else { return }
        Task { await start() }
    }

    func select(_ input: AudioInput) {
        do {
            try inputSelector.select(input)
            refreshRoute()
        } catch {
            ErrorLog.shared.error("Audio", "Couldn't switch input", error: error)
        }
    }

    // MARK: Private

    private func start() async {
        guard capture == nil, status != .starting else { return }
        status = .starting

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        guard users > 0 else {
            status = .off
            return
        }

        do {
            try session.beginRecording()
            try startCapture()
        } catch {
            ErrorLog.shared.error("Audio", "Microphone couldn't start", error: error)
            session.endRecording()
            status = .unavailable(error.localizedDescription)
        }
    }

    private func startCapture() throws {
        refreshRoute()
        let monitor = monitorInput && canMonitorInput
        let capture = try MicrophoneCapture(profile: inputProfile.detectorProfile(referenceA: referenceA), sensitivity: sensitivity, monitorInput: monitor)
        try capture.start()
        self.capture = capture
        capturedSince = .now
        latency = capture.latency
        status = .listening
        listen(to: capture)
    }

    private func stop() {
        stopCapture()
        if status == .listening { session.endRecording() }
        level = 0
        levelDecibels = -120
        pitch = nil
        status = .off
    }

    private func stopCapture() {
        listener?.cancel()
        listener = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        capture?.stop()
        capture = nil
        for pitch in heardPitches.sorted() { onEvent?(.noteOff(pitch: pitch)) }
        heardPitches = []
    }

    /// Settings changed while listening: rebuild the detector for the new profile.
    private func rebuildIfListening() {
        guard capture != nil else { return }
        stopCapture()
        do {
            try startCapture()
        } catch {
            ErrorLog.shared.error("Audio", "Microphone couldn't restart", error: error)
            status = .unavailable(error.localizedDescription)
        }
    }

    /// A new input device or an interruption stopped the engine: rebuild it for the new hardware.
    private func restartCapture() {
        guard users > 0, capture != nil, Date.now.timeIntervalSince(capturedSince) > 1 else { return }
        rebuildIfListening()
    }

    private func refreshRoute() {
        inputs = inputSelector.availableInputs
        currentInput = inputSelector.currentInput
        isSpeakerOutput = inputSelector.isSpeakerOutput
    }

    private func listen(to capture: MicrophoneCapture) {
        let updates = capture.updates
        listener = Task { [weak self] in
            for await update in updates {
                guard let self, !Task.isCancelled else { return }
                apply(update)
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: capture.engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartCapture() }
        }
    }

    private func apply(_ update: MicrophoneCapture.Update) {
        for event in update.events { onEvent?(event) }
        if heardPitches != update.sounding { heardPitches = update.sounding }
        if pitch != update.pitch { pitch = update.pitch }
        levelDecibels = update.level
        let meter = Double(min(max((update.level + 70) / 70, 0), 1))
        if abs(meter - level) > 0.01 { level = meter }
        if let prior = priorProvider?() { capture?.setPrior(prior) }
    }
}
