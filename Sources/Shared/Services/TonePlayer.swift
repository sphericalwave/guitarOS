import AVFoundation
import Synchronization
import DiagnosticsKit

/// Plays reference tones (plucked strings from `PluckSynth`) through its own output engine. Rendered once
/// per request on a background task, then streamed by an `AVAudioSourceNode`. The mic stays on `AudioHub`.
@MainActor
final class TonePlayer {
    private final class Queue: @unchecked Sendable {
        let state = Mutex<(samples: [Float], position: Int)>(([], 0))
    }

    private let engine = AVAudioEngine()
    private let queue = Queue()
    private let sampleRate: Double
    private var source: AVAudioSourceNode?
    /// Host-clock time the current tone finishes, so callers can wait before listening.
    private(set) var playingUntil: TimeInterval = 0

    init() {
        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let queue = queue
        let node = AVAudioSourceNode { (_, _, frameCount, bufferList) -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            queue.state.withLock { state in
                for index in 0..<Int(frameCount) {
                    out[index] = state.position < state.samples.count ? state.samples[state.position] : 0
                    state.position += 1
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    }

    /// Plays MIDI pitches `spacing` seconds apart (0 for a block chord), each ringing `ring` seconds.
    func play(_ pitches: [UInt8], a4: Double, spacing: TimeInterval, ring: TimeInterval = 1.2) {
        guard !pitches.isEmpty else { return }
        let synth = PluckSynth(sampleRate: sampleRate)
        let duration = Double(pitches.count - 1) * spacing + ring
        let plucks = PluckSynth.sequence(pitches, a4: a4, spacing: spacing)
        playingUntil = AVAudioTime.seconds(forHostTime: mach_absolute_time()) + duration + 0.05
        let queue = queue
        Task.detached(priority: .userInitiated) {
            let samples = synth.render(plucks, duration: duration)
            queue.state.withLock { $0 = (samples, 0) }
        }
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                ErrorLog.shared.error("Tones", "Reference tone couldn't play", error: error)
            }
        }
    }

    var isPlaying: Bool { AVAudioTime.seconds(forHostTime: mach_absolute_time()) < playingUntil }

    func stop() {
        queue.state.withLock { $0 = ([], 0) }
        playingUntil = 0
        engine.stop()
    }
}
