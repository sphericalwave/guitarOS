import AVFoundation
import Foundation
import Observation
import SwiftData
import ScrollKit
import DiagnosticsKit

/// Strum or pick on the click: a one-bar count-in, then a few bars judged strike by strike against the grid.
@Observable
@MainActor
final class RhythmDrillViewModel {
    enum Phase: Equatable { case ready, countingIn, playing, finished(RhythmJudge.Summary) }

    let bpm: Double
    let subdivision: RhythmJudge.Subdivision
    let bars: Int
    let beatsPerBar = 4
    private(set) var phase: Phase = .ready
    private(set) var strikes: [RhythmJudge.Strike] = []
    private(set) var summary = RhythmJudge.Summary()
    /// Current beat within the bar (0-based) for the beat dots.
    private(set) var beatInBar = 0
    /// The last strike's offset, for the needle.
    private(set) var lastOffset: Double?

    let audio: AudioHub
    let metronome: MetronomeViewModel
    let cards: CardStore
    let context: ModelContext
    var logsStandalone = true

    static let countInBars = 1
    var key: String { "rhythm:\(subdivision.key)" }
    var title: String { "\(subdivision.title) at \(Int(bpm)) BPM" }
    var best: Double? { cards.all(kind: .rhythm).first { $0.key == key }?.best }
    var totalBeats: Int { (Self.countInBars + bars) * beatsPerBar }
    var progress: Double { phase == .ready ? 0 : min(1, Double(beatIndex) / Double(totalBeats)) }

    @ObservationIgnored private var judge: RhythmJudge
    @ObservationIgnored private var listenerID: UUID?
    @ObservationIgnored private var beatWatcher: Task<Void, Never>?
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var startedAt = Date.now

    init(bpm: Double, subdivision: RhythmJudge.Subdivision, bars: Int, audio: AudioHub, metronome: MetronomeViewModel, context: ModelContext) {
        self.bpm = bpm
        self.subdivision = subdivision
        self.bars = bars
        self.audio = audio
        self.metronome = metronome
        self.context = context
        cards = CardStore(context: context)
        let first = Double(Self.countInBars * beatsPerBar)
        judge = RhythmJudge(bpm: bpm, subdivision: subdivision, range: first...(first + Double(bars * beatsPerBar) - 1 / Double(subdivision.rawValue)))
    }

    func start() {
        judge.reset()
        strikes = []
        summary = RhythmJudge.Summary()
        lastOffset = nil
        beatIndex = 0
        beatInBar = 0
        startedAt = .now
        phase = .countingIn
        audio.acquire()
        let listener = OnsetListener(gateDecibels: audio.inputProfile.gateDecibels, sensitivity: audio.sensitivity) { [weak self] time in
            Task { @MainActor in self?.heard(at: time) }
        }
        listenerID = audio.addFrameListener { buffer, time in listener.handle(buffer, time) }
        metronome.bpm = bpm
        metronome.beatsPerBar = beatsPerBar
        metronome.start()
        beatWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                self?.tick()
            }
        }
    }

    func stop() {
        guard phase != .ready else { return }
        teardown()
        if case .finished = phase {} else { phase = .ready }
    }

    func reset() { phase = .ready }

    // MARK: Private

    private func teardown() {
        beatWatcher?.cancel()
        beatWatcher = nil
        if let listenerID { audio.removeFrameListener(listenerID) }
        listenerID = nil
        metronome.stop()
        audio.release()
    }

    private func tick() {
        guard phase == .countingIn || phase == .playing else { return }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        guard let beat = metronome.beat(atHostTime: now) else { return }
        beatIndex = max(0, Int(beat.rounded(.down)))
        beatInBar = beatIndex % beatsPerBar
        if phase == .countingIn, beat >= Double(Self.countInBars * beatsPerBar) - 0.1 { phase = .playing }
        // One extra beat past the last grid point so a late strike still lands.
        if beat >= judge.range.upperBound + 1 { finish() }
    }

    private func heard(at hostTime: TimeInterval) {
        guard phase == .countingIn || phase == .playing, let beat = metronome.beat(atHostTime: hostTime) else { return }
        guard let strike = judge.strike(atBeat: beat) else { return }
        strikes.append(strike)
        lastOffset = strike.offset
        summary = judge.summary
    }

    private func finish() {
        let result = judge.summary
        teardown()
        let card = cards.card(kind: .rhythm, key: key)
        card.attempts += 1
        if result.accuracy >= 0.75 { card.correct += 1 }
        card.lastPracticed = .now
        // Best is the tightest spread at a reasonable accuracy.
        if result.accuracy >= 0.75, result.strikes >= 4, result.standardDeviation < (card.best ?? .infinity) { card.best = result.standardDeviation }
        SM2.update(card: card, quality: RhythmJudge.quality(result))
        if logsStandalone { logStandalone(result) }
        do { try context.save() } catch { ErrorLog.shared.error("Rhythm", "Couldn't save the pass", error: error) }
        summary = result
        phase = .finished(result)
    }

    private func logStandalone(_ result: RhythmJudge.Summary) {
        let session = PracticeSession(startedAt: startedAt, goalMinutes: max(UserDefaults.standard.integer(forKey: SettingsKey.dailyGoalMinutes), 20))
        session.duration = Date.now.timeIntervalSince(startedAt)
        session.endedAt = .now
        context.insert(session)
        context.insert(block(for: result, in: session))
    }

    func block(for result: RhythmJudge.Summary, in session: PracticeSession?) -> PracticeBlock {
        let block = PracticeBlock(kind: RoutineKind.rhythm.rawValue, title: title, startedAt: startedAt)
        block.duration = Date.now.timeIntervalSince(startedAt)
        block.attempts = result.strikes + result.missed
        block.correct = result.onTime
        block.score = result.standardDeviation
        block.bpm = Int(bpm)
        block.session = session
        return block
    }
}

/// Runs an `OnsetAnalyzer` on the hub's input buffers, off the main thread, and reports each strike's host time
/// with the input's own latency taken off.
nonisolated final class OnsetListener: @unchecked Sendable {
    private let gateDecibels: Float
    private let sensitivity: Double
    private let onStrike: @Sendable (TimeInterval) -> Void
    private var analyzer: OnsetAnalyzer?

    init(gateDecibels: Float, sensitivity: Double, onStrike: @escaping @Sendable (TimeInterval) -> Void) {
        self.gateDecibels = gateDecibels
        self.sensitivity = sensitivity
        self.onStrike = onStrike
    }

    func handle(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        if analyzer == nil { analyzer = OnsetAnalyzer(sampleRate: buffer.format.sampleRate, gateDecibels: gateDecibels, sensitivity: sensitivity) }
        guard let analyzer else { return }
        let start = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : AVAudioTime.seconds(forHostTime: mach_absolute_time()) - Double(buffer.frameLength) / buffer.format.sampleRate
        for strike in analyzer.process(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), startTime: start) { onStrike(strike) }
    }
}
