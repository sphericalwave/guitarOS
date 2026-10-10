import Foundation
import Observation
import PitchKit

/// Drives the tuner screen from `AudioHub`: a smoothed reading against the chosen tuning and
/// reference A, plus the "can't hear anything" hint.
@Observable
@MainActor
final class TunerViewModel {
    enum Reference: String, CaseIterable, Identifiable {
        case standard, alternate, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: "440"
            case .alternate: "432"
            case .custom: "Custom"
            }
        }
    }

    private(set) var reading: TunerModel.Reading?
    /// Set when the input has been near silence for a while, so the screen can say what to check.
    private(set) var cannotHear = false

    let audio: AudioHub
    var tuning: Tuning

    /// Seconds of silence before the hint shows.
    static let silenceHint: TimeInterval = 3

    @ObservationIgnored private var recent: [Double] = []
    @ObservationIgnored private var lastHeard = Date.now
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(audio: AudioHub, tuning: Tuning) {
        self.audio = audio
        self.tuning = tuning
    }

    var referenceA: Double {
        get { audio.referenceA }
        set { audio.referenceA = ReferencePitch.clamped(newValue) }
    }

    func start() {
        audio.acquire()
        lastHeard = .now
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        audio.release()
        reading = nil
        recent = []
    }

    /// Polls the hub's latest pitch. Polling at 20 Hz is simpler than observation plumbing and
    /// well under the 400 ms feedback threshold.
    private func tick() {
        if let pitch = audio.pitch {
            recent.append(pitch.frequency)
            if recent.count > TunerModel.smoothingWindow { recent.removeFirst() }
            if let frequency = TunerModel.smoothed(recent) {
                reading = TunerModel.reading(frequency: frequency, tuning: tuning, referenceA: referenceA)
            }
            lastHeard = .now
            cannotHear = false
        } else {
            if !recent.isEmpty { recent.removeFirst() }
            if recent.isEmpty, reading != nil { reading = nil }
            cannotHear = audio.status == .listening && Date.now.timeIntervalSince(lastHeard) > Self.silenceHint
        }
    }
}
