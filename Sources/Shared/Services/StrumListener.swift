import AVFoundation
import PitchKit

/// Runs a `StrumAnalyzer` on the hub's input buffers, off the main thread, and hands each strum back.
/// Times are host-clock seconds, like the hub's note events.
nonisolated final class StrumListener: @unchecked Sendable {
    private let profile: InstrumentProfile
    private let sensitivity: Double
    private let candidates: Set<UInt8>
    private let onStrum: @Sendable (StrumAnalyzer.Strum) -> Void
    /// Built from the first buffer, which says the sample rate. Touched only on the tap's queue.
    private var analyzer: StrumAnalyzer?

    init(profile: InstrumentProfile, sensitivity: Double, candidates: Set<UInt8>, onStrum: @escaping @Sendable (StrumAnalyzer.Strum) -> Void) {
        self.profile = profile
        self.sensitivity = sensitivity
        self.candidates = candidates
        self.onStrum = onStrum
    }

    func handle(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        if analyzer == nil {
            let analyzer = StrumAnalyzer(sampleRate: buffer.format.sampleRate, profile: profile, sensitivity: sensitivity)
            analyzer.candidates = candidates
            self.analyzer = analyzer
        }
        guard let analyzer else { return }
        let start = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : AVAudioTime.seconds(forHostTime: mach_absolute_time()) - Double(buffer.frameLength) / buffer.format.sampleRate
        let strums = analyzer.process(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), startTime: start)
        for strum in strums { onStrum(strum) }
    }
}
