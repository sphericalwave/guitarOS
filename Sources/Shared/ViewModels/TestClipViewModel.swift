import Foundation
import Observation
import DiagnosticsKit

/// Records labelled strums for the chord-detection gate: pick the chord, name the guitar, strum once while
/// it records a few seconds. Clips are listed below to share or delete.
@Observable
@MainActor
final class TestClipViewModel {
    enum Phase: Equatable { case idle, recording, saved(TestClip), failed(String) }

    var chord: ChordVoicing
    var guitar = ""
    private(set) var phase: Phase = .idle
    private(set) var clips: [TestClip] = []
    private(set) var elapsed: TimeInterval = 0

    let audio: AudioHub
    let store: TestClipStore

    /// Long enough for a strum and its ring.
    static let maxDuration: TimeInterval = 5

    @ObservationIgnored private var recorder: ClipRecorder?
    @ObservationIgnored private var listenerID: UUID?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var clip: TestClip?

    init(audio: AudioHub, store: TestClipStore = TestClipStore(), chord: ChordVoicing) {
        self.audio = audio
        self.store = store
        self.chord = chord
        clips = store.clips()
    }

    func appear() { audio.acquire() }
    func disappear() {
        if phase == .recording { stopRecording() }
        audio.release()
    }

    var isListening: Bool { audio.status == .listening }

    func startRecording(tuning: Tuning) {
        guard phase != .recording, isListening else { return }
        let clip = TestClip(
            id: UUID(), chord: chord.name, guitar: guitar.trimmingCharacters(in: .whitespaces), input: audio.inputProfile.rawValue,
            recordedAt: .now, duration: 0, sampleRate: 0, referenceA: audio.referenceA, tuning: tuning.description
        )
        let recorder = ClipRecorder(store: store, clip: clip)
        self.clip = clip
        self.recorder = recorder
        elapsed = 0
        phase = .recording
        listenerID = audio.addFrameListener { buffer, time in recorder.handle(buffer, time) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                elapsed = recorder.duration
                if elapsed >= Self.maxDuration { stopRecording(); return }
            }
        }
    }

    func stopRecording() {
        ticker?.cancel()
        ticker = nil
        if let listenerID { audio.removeFrameListener(listenerID) }
        listenerID = nil
        guard let recorder, var clip else { phase = .idle; return }
        clip.duration = recorder.stop()
        self.recorder = nil
        self.clip = nil
        if let error = recorder.error {
            ErrorLog.shared.error("Clips", "Couldn't record the clip", error: error)
            try? store.delete(clip)
            phase = .failed(error.localizedDescription)
            return
        }
        guard clip.duration > 0.2 else {
            try? store.delete(clip)
            phase = .failed("Nothing was recorded. Is the microphone on?")
            return
        }
        do {
            try store.save(clip)
            clips = store.clips()
            phase = .saved(clip)
        } catch {
            ErrorLog.shared.error("Clips", "Couldn't save the clip's label", error: error)
            phase = .failed(error.localizedDescription)
        }
    }

    func delete(_ clip: TestClip) {
        do {
            try store.delete(clip)
            clips = store.clips()
            if case .saved(let saved) = phase, saved == clip { phase = .idle }
        } catch {
            ErrorLog.shared.error("Clips", "Couldn't delete the clip", error: error)
        }
    }

    func audioURL(for clip: TestClip) -> URL { store.audioURL(for: clip) }
    func metadataURL(for clip: TestClip) -> URL { store.metadataURL(for: clip) }
    /// Every clip's audio and label, for one share.
    var allURLs: [URL] { clips.flatMap { [store.audioURL(for: $0), store.metadataURL(for: $0)] } }
}
