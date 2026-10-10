import Foundation
import Observation
import DiagnosticsKit

/// Drives the metronome tool and the click inside drills.
@Observable
@MainActor
final class MetronomeViewModel {
    private(set) var isRunning = false
    private(set) var beat: ClickTrack.Beat?
    var bpm: Double { didSet { bpm = min(max(bpm, ClickSchedule.bpmRange.lowerBound), ClickSchedule.bpmRange.upperBound); track.set(bpm: bpm) } }
    var beatsPerBar: Int { didSet { track.set(beatsPerBar: beatsPerBar) } }

    @ObservationIgnored private let track: ClickTrack
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var taps: [TimeInterval] = []

    init(bpm: Double, beatsPerBar: Int = 4) {
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        track = ClickTrack(bpm: bpm, beatsPerBar: beatsPerBar)
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        do {
            try track.start()
            isRunning = true
            listener = Task { [weak self] in
                for await beat in self?.track.beats ?? AsyncStream { $0.finish() } {
                    guard let self else { return }
                    self.beat = beat
                }
            }
        } catch {
            ErrorLog.shared.error("Metronome", "Click couldn't start", error: error)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        track.stop()
        isRunning = false
        beat = nil
    }

    /// Tap tempo: a few taps set the BPM; a pause starts over.
    func tap() {
        let now = Date.now.timeIntervalSinceReferenceDate
        if let last = taps.last, now - last > 2.5 { taps = [] }
        taps.append(now)
        if let value = ClickSchedule.bpm(fromTaps: taps) { bpm = value }
    }
}
