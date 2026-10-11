import AVFoundation
import Foundation
import Observation
import SwiftData
import ScrollKit
import DiagnosticsKit
import PitchKit
import PlayAlongKit

/// Plays one scale position up and down. Wait mode advances when the mic hears the next note; timed mode
/// runs the click and judges each note against the beat (PlayAlongKit), stepping the BPM up after a clean pass.
@Observable
@MainActor
final class ScaleDrillViewModel {
    enum Phase: Equatable { case ready, countingIn, playing, finished(ScaleDrill.Result) }

    let position: ScalePosition
    let mode: ScaleDrill.Mode
    let bpm: Double
    let sequence: [FretPosition]
    let pitches: [UInt8]
    private(set) var phase: Phase = .ready
    /// Next note to play, as an index into `sequence`.
    private(set) var index = 0
    /// Per note: true = hit, false = missed (timed) or needed a wrong try first (wait).
    private(set) var results: [Int: Bool] = [:]
    private(set) var heardNote: Int?
    /// Where a wrong note was heard, if it's in the box, for the red dot.
    private(set) var wrongPosition: FretPosition?
    private(set) var hits = 0
    private(set) var missed = 0
    private(set) var extras = 0

    let audio: AudioHub
    let cards: CardStore
    let context: ModelContext
    let metronome: MetronomeViewModel?
    /// Set when the drill runs inside a session, so the block is logged there instead of standalone.
    var logsStandalone = true

    var nextPosition: FretPosition? { index < sequence.count ? sequence[index] : nil }
    var progress: Double { sequence.isEmpty ? 0 : Double(index) / Double(sequence.count) }
    var title: String { "\(position.scale.name(preferSharps: true)) · position \(position.index)" }
    var best: Double? { cards.all(kind: .scaleShape).first { $0.key == position.key }?.best }

    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var startHost: TimeInterval = 0
    @ObservationIgnored private var judge: PlayAlongJudge?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var stable: [Int] = []
    @ObservationIgnored private var clearedAt = Date.distantPast
    @ObservationIgnored private var wrongOnThisNote = false

    init(position: ScalePosition, mode: ScaleDrill.Mode, bpm: Double, audio: AudioHub, context: ModelContext, metronome: MetronomeViewModel?) {
        self.position = position
        self.mode = mode
        self.bpm = bpm
        self.audio = audio
        self.context = context
        self.metronome = mode == .timed ? metronome : nil
        cards = CardStore(context: context)
        sequence = position.sequence
        pitches = sequence.map { position.pitch(at: $0) }
    }

    func start() {
        index = 0
        results = [:]
        hits = 0; missed = 0; extras = 0
        heardNote = nil
        wrongPosition = nil
        stable = []
        wrongOnThisNote = false
        startedAt = .now
        clearedAt = .now
        audio.acquire()
        switch mode {
        case .wait:
            phase = .playing
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(40))
                    self?.tickWait()
                }
            }
        case .timed:
            guard let metronome else { return }
            metronome.bpm = bpm
            var judge = PlayAlongJudge(notes: ScaleDrill.expectedNotes(pitches: pitches, bpm: bpm))
            judge.reset()
            self.judge = judge
            metronome.start()
            startHost = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            phase = .countingIn
            audio.onEvent = { [weak self] event, time in
                guard let self, case let .noteOn(pitch, _) = event else { return }
                press(pitch: pitch, at: time - startHost)
            }
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    self?.tickTimed()
                }
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
        ticker?.cancel()
        ticker = nil
        audio.onEvent = nil
        metronome?.stop()
        audio.release()
    }

    /// Wait mode: a note has to hold for a couple of readings; the expected one clears, any other is a stray.
    private func tickWait() {
        guard phase == .playing, let expected = nextPosition else { return }
        guard let pitch = audio.pitch else {
            stable = []
            if heardNote != nil { heardNote = nil }
            return
        }
        let nearest = PitchMath.note(nearest: pitch.frequency, a4: audio.referenceA)
        if heardNote != nearest.note { heardNote = nearest.note }
        guard Date.now.timeIntervalSince(clearedAt) > ScaleDrill.settleTime else { return }
        if stable.last == nearest.note { stable.append(nearest.note) } else { stable = [nearest.note] }
        guard stable.count == ScaleDrill.stableReadings else { return }
        if nearest.note == Int(position.pitch(at: expected)) {
            results[index] = !wrongOnThisNote
            if wrongOnThisNote { missed += 1 } else { hits += 1 }
            wrongOnThisNote = false
            wrongPosition = nil
            index += 1
            clearedAt = .now
            if index >= sequence.count { finish() }
        } else if !wrongOnThisNote || wrongPosition.map({ Int(position.pitch(at: $0)) }) != nearest.note {
            // Playing the previous note again while it rings isn't a stray; another note is.
            guard index == 0 || nearest.note != Int(position.pitch(at: sequence[index - 1])) else { return }
            extras += 1
            wrongOnThisNote = true
            wrongPosition = position.positions.first { Int(position.pitch(at: $0)) == nearest.note }
        }
    }

    private func press(pitch: UInt8, at time: TimeInterval) {
        guard phase == .countingIn || phase == .playing, judge != nil else { return }
        heardNote = Int(pitch)
        if let id = judge!.press(pitch: pitch, at: time) {
            results[id] = true
            wrongPosition = nil
        } else if time >= Double(ScaleDrill.countInBeats) * 60 / bpm - PlayAlongJudge.defaultWindow {
            wrongPosition = position.positions.first { position.pitch(at: $0) == pitch }
        }
        syncJudge()
    }

    private func tickTimed() {
        guard phase == .countingIn || phase == .playing, judge != nil else { return }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - startHost
        let beat = 60 / bpm
        if phase == .countingIn, now >= Double(ScaleDrill.countInBeats) * beat - PlayAlongJudge.defaultWindow { phase = .playing }
        judge!.advance(to: now)
        syncJudge()
        let lastTime = Double(ScaleDrill.countInBeats + pitches.count - 1) * beat
        if now > lastTime + PlayAlongJudge.defaultWindow { finish() }
    }

    private func syncJudge() {
        guard let judge else { return }
        for (id, judgement) in judge.results where results[id] == nil {
            results[id] = judgement != .missed
        }
        hits = judge.summary.hits
        missed = judge.summary.missed
        extras = judge.summary.extras
        index = (0..<pitches.count).first { results[$0] == nil } ?? pitches.count
    }

    private func finish() {
        let seconds = Date.now.timeIntervalSince(startedAt)
        let result = ScaleDrill.Result(mode: mode, bpm: mode == .timed ? bpm : 0, notes: pitches.count, hits: hits, missed: missed, extras: extras,
                                       seconds: seconds, averageOffset: judge?.summary.averageOffset ?? 0)
        teardown()
        let card = cards.card(kind: .scaleShape, key: position.key)
        card.attempts += 1
        if result.isClean { card.correct += 1 }
        card.lastPracticed = .now
        if mode == .timed, result.isClean, bpm > (card.best ?? 0) { card.best = bpm }
        SM2.update(card: card, quality: ScaleDrill.quality(result))
        if logsStandalone { logStandalone(result) }
        do { try context.save() } catch { ErrorLog.shared.error("Scales", "Couldn't save the pass", error: error) }
        phase = .finished(result)
    }

    /// Outside a session, a pass still counts as practice: a one-block session of its own.
    private func logStandalone(_ result: ScaleDrill.Result) {
        let session = PracticeSession(startedAt: startedAt, goalMinutes: UserDefaults.standard.integer(forKey: SettingsKey.dailyGoalMinutes).nonZero ?? 20)
        session.duration = result.seconds
        session.endedAt = .now
        context.insert(session)
        context.insert(block(for: result, in: session))
    }

    func block(for result: ScaleDrill.Result, in session: PracticeSession?) -> PracticeBlock {
        let block = PracticeBlock(kind: RoutineKind.scale.rawValue, title: title, startedAt: startedAt)
        block.duration = result.seconds
        block.attempts = result.notes
        block.correct = result.hits
        block.score = result.accuracy
        block.bpm = mode == .timed ? Int(bpm) : nil
        block.session = session
        return block
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
