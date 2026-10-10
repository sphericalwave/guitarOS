import AVFoundation
import Synchronization

/// Sample-accurate metronome: an `AVAudioSourceNode` writes short clicks at exact sample positions from
/// a `ClickSchedule`, so the beat grid never drifts and maps back to host time for judging.
/// Runs on its own output-only engine for now (see PLAN M5).
nonisolated final class ClickTrack: @unchecked Sendable {
    struct Beat: Sendable, Equatable {
        var index: Int
        var isAccent: Bool
    }

    private struct State: Sendable {
        var schedule: ClickSchedule
        var isRunning = false
        var startSample = 0
        var rendered = 0
        var lastBeat = -1
        var volume: Float = 0.8
    }

    /// Reference wrapper so the render block can capture the (noncopyable) mutex.
    private final class Shared: @unchecked Sendable {
        let state: Mutex<State>
        init(_ state: State) { self.state = Mutex(state) }
    }

    private let engine = AVAudioEngine()
    private let shared: Shared
    let sampleRate: Double
    /// Beats as they sound, for the UI's beat indicator.
    let beats: AsyncStream<Beat>
    private let continuation: AsyncStream<Beat>.Continuation
    private var source: AVAudioSourceNode?

    init(bpm: Double = 100, beatsPerBar: Int = 4) {
        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        shared = Shared(State(schedule: ClickSchedule(bpm: bpm, beatsPerBar: beatsPerBar, sampleRate: sampleRate)))
        (beats, continuation) = AsyncStream.makeStream(of: Beat.self, bufferingPolicy: .bufferingNewest(4))
        let node = Self.makeSource(shared: shared, sampleRate: sampleRate, continuation: continuation)
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    }

    var isRunning: Bool { shared.state.withLock { $0.isRunning } }

    func start() throws {
        shared.state.withLock {
            $0.isRunning = true
            $0.startSample = $0.rendered
            $0.lastBeat = -1
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func stop() {
        shared.state.withLock { $0.isRunning = false }
        engine.stop()
    }

    func set(bpm: Double) {
        shared.state.withLock {
            let clamped = min(max(bpm, ClickSchedule.bpmRange.lowerBound), ClickSchedule.bpmRange.upperBound)
            guard clamped != $0.schedule.bpm else { return }
            // Re-anchor so the next beat lands one new beat after the last one, not somewhere mid-bar.
            let elapsedBeats = $0.lastBeat + 1
            $0.schedule.bpm = clamped
            $0.startSample = $0.rendered - Int(Double(elapsedBeats) * $0.schedule.samplesPerBeat) + Int($0.schedule.samplesPerBeat)
            $0.lastBeat = elapsedBeats - 1
        }
    }

    func set(beatsPerBar: Int) {
        shared.state.withLock { $0.schedule.beatsPerBar = max(1, beatsPerBar) }
    }

    /// Click samples: a 4 ms sine burst, higher and louder on the accent.
    private static func makeSource(shared: Shared, sampleRate: Double, continuation: AsyncStream<Beat>.Continuation) -> AVAudioSourceNode {
        let clickLength = Int(sampleRate * 0.004)
        return AVAudioSourceNode { (_: UnsafeMutablePointer<ObjCBool>, _: UnsafePointer<AudioTimeStamp>, frameCount: AVAudioFrameCount, bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
            render(shared: shared, sampleRate: sampleRate, clickLength: clickLength, continuation: continuation, frameCount: Int(frameCount), bufferList: bufferList)
        }
    }

    private static func render(shared: Shared, sampleRate: Double, clickLength: Int, continuation: AsyncStream<Beat>.Continuation,
                               frameCount count: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        for i in 0..<count { out[i] = 0 }

        shared.state.withLock { st in
            defer { st.rendered += count }
            guard st.isRunning else { return }
            let range = st.rendered..<(st.rendered + count)
            // Clicks that started in a previous buffer may still be ringing into this one.
            let lookback = (st.rendered - clickLength)..<(st.rendered + count)
            for click in st.schedule.clicks(in: lookback, start: st.startSample) {
                let frequency: Double = click.isAccent ? 1800 : 1200
                let gain: Double = Double(st.volume) * (click.isAccent ? 1 : 0.7)
                let step: Double = 2 * Double.pi * frequency / sampleRate
                for n in 0..<clickLength {
                    let sample = click.sample + n
                    guard range.contains(sample) else { continue }
                    let envelope: Double = 1 - Double(n) / Double(clickLength)
                    let value: Double = gain * envelope * sin(step * Double(n))
                    out[sample - st.rendered] += Float(value)
                }
                if click.beat > st.lastBeat, range.contains(click.sample) {
                    st.lastBeat = click.beat
                    continuation.yield(Beat(index: click.beat, isAccent: click.isAccent))
                }
            }
        }
        return noErr
    }
}
