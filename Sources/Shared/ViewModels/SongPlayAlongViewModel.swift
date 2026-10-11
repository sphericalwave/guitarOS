import AVFoundation
import Foundation
import Observation
import SwiftData
import DiagnosticsKit
import PitchKit
import PlayAlongKit

/// Practises one track of a song: the tab scrolls past the playhead while the backing plays. Wait mode holds
/// at each note until the mic hears it; play-along keeps going and judges every note against the beat.
@Observable
@MainActor
final class SongPlayAlongViewModel {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case wait, playAlong
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wait: "Wait for me"
            case .playAlong: "Play along"
            }
        }
    }

    struct Result: Equatable {
        var hits: Int
        var missed: Int
        var extras: Int
        var accuracy: Double
        var seconds: TimeInterval
    }

    let song: Song
    let score: TabScore
    let timeline: TabTimeline
    private(set) var trackIndex: Int
    var mode: Mode = .wait { didSet { if mode != oldValue { restartJudging() } } }
    /// Now, in song seconds (negative during the count-in). Updated every tick.
    private(set) var position: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isHolding = false
    /// Notes the wait gate is waiting on.
    private(set) var requiredPitches: Set<UInt8> = []
    /// Per timeline note id: hit or missed, as judged so far.
    private(set) var results: [Int: Bool] = [:]
    private(set) var summary = PlayAlongJudge.Summary()
    private(set) var result: Result?
    /// A–B loop by unrolled measure index, inclusive.
    var loopMeasures: ClosedRange<Int>? { didSet { applyLoop() } }
    var rate: Double = 1 { didSet { player?.rate = rate } }
    var playsMyTrack = false { didSet { applyMutes() } }
    var isCountInOn = true { didSet { player?.isCountInOn = isCountInOn } }

    let audio: AudioHub
    let context: ModelContext
    private(set) var player: SongPlayer?
    private(set) var loadError: String?
    var logsStandalone = true

    var expected: [ExpectedNote] { timeline.expectedNotes(track: trackIndex) }
    var track: TabTrack { score.tracks[trackIndex] }
    var duration: TimeInterval { timeline.duration }
    var title: String { song.title.isEmpty ? "Song" : song.title }

    @ObservationIgnored private var judge: PlayAlongJudge?
    @ObservationIgnored private var runner: WaitRunner?
    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var stable: [Int] = []
    @ObservationIgnored private var heard: Set<UInt8> = []

    init(song: Song, score: TabScore, audio: AudioHub, context: ModelContext) {
        self.song = song
        self.score = score
        self.audio = audio
        self.context = context
        timeline = TabTimeline(score: score)
        trackIndex = score.tracks.indices.contains(song.trackIndex) ? song.trackIndex : (score.guitarTracks.first ?? 0)
        position = song.lastPosition
    }

    /// Builds the player and starts listening. Call once the screen is up.
    func prepare() {
        guard player == nil else { return }
        do {
            let player = try SongPlayer(timeline: timeline, score: score)
            player.onTick = { [weak self] now in self?.tick(now) }
            player.onLoop = { [weak self] in self?.restartJudging() }
            player.isCountInOn = isCountInOn
            player.rate = rate
            self.player = player
            applyMutes()
            seek(to: max(0, min(song.lastPosition, duration - 1)))
        } catch {
            ErrorLog.shared.error("Songs", "Couldn't start playback", error: error)
            loadError = error.localizedDescription
        }
        audio.acquire()
        audio.priorProvider = { [weak self] in
            guard let self else { return .init() }
            return .init(expected: requiredPitches.union(upcomingPitches()), suppressed: [])
        }
        audio.onEvent = { [weak self] event, time in
            guard let self, case let .noteOn(pitch, _) = event else { return }
            heardNoteOn(pitch, at: time)
        }
        restartJudging()
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        if player.position() >= duration { seek(to: 0) }
        result = nil
        startedAt = .now
        do { try player.play() } catch { ErrorLog.shared.error("Songs", "Couldn't play", error: error) }
        isPlaying = player.isPlaying
    }

    func pause() {
        player?.pause()
        isPlaying = false
        isHolding = false
        requiredPitches = []
        song.lastPosition = max(0, position)
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: time)
        position = time
        restartJudging()
    }

    func choose(track: Int) {
        guard score.tracks.indices.contains(track) else { return }
        trackIndex = track
        song.trackIndex = track
        applyMutes()
        restartJudging()
    }

    /// Leaving the screen: stop sound, keep the position and best.
    func close() {
        pause()
        player?.shutdown()
        player = nil
        audio.onEvent = nil
        audio.priorProvider = nil
        audio.release()
        do { try context.save() } catch { ErrorLog.shared.error("Songs", "Couldn't save the song", error: error) }
    }

    // MARK: Private

    private func applyMutes() {
        player?.mutedTracks = playsMyTrack ? [] : [trackIndex]
    }

    private func applyLoop() {
        guard let player else { return }
        if let loopMeasures, let first = timeline.measures[safe: loopMeasures.lowerBound], let last = timeline.measures[safe: loopMeasures.upperBound] {
            player.loop = first.start...(last.start + last.duration)
            if !player.loop!.contains(position) { seek(to: first.start) }
        } else {
            player.loop = nil
        }
    }

    private func restartJudging() {
        let notes = expected
        var judge = PlayAlongJudge(notes: notes)
        judge.reset()
        var runner = WaitRunner(gate: WaitGate(notes: notes))
        runner.seek(to: position)
        self.judge = judge
        self.runner = runner
        results = [:]
        summary = PlayAlongJudge.Summary()
        isHolding = false
        requiredPitches = []
        heard = []
    }

    /// Pitches due in the next beat or so, so the detector leans their way.
    private func upcomingPitches() -> Set<UInt8> {
        let from = position, to = position + 0.6
        return Set(expected.filter { $0.time >= from && $0.time <= to }.map(\.pitch))
    }

    private func tick(_ now: TimeInterval) {
        position = now
        switch mode {
        case .playAlong:
            guard judge != nil else { return }
            judge!.advance(to: now)
            syncJudge()
            if now > duration + PlayAlongJudge.defaultWindow { finishPass() }
        case .wait:
            guard runner != nil, let player else { return }
            let action = runner!.tick(position: now, pressed: audio.heardPitches.union(heard))
            heard = []
            switch action {
            case .hold(let at, let pitches):
                player.pause()
                player.seek(to: at)
                isHolding = true
                requiredPitches = pitches
            case .resume:
                isHolding = false
                requiredPitches = []
                try? player.play()
            case .none:
                if isHolding { requiredPitches = runner!.remainingPitches(pressed: audio.heardPitches.union(heard)) }
            }
            if runner!.isFinished, now > duration { finishPass() }
        }
    }

    private func heardNoteOn(_ pitch: UInt8, at hostTime: TimeInterval) {
        guard let player else { return }
        switch mode {
        case .playAlong:
            guard judge != nil, player.isPlaying else { return }
            let at = player.position(atHostTime: hostTime)
            if let id = judge!.press(pitch: pitch, at: at) { results[id] = true }
            syncJudge()
        case .wait:
            // While holding, playback is paused and ticks stop: feed the runner by hand.
            heard.insert(pitch)
            if isHolding, runner != nil {
                let action = runner!.tick(position: position, pressed: audio.heardPitches.union(heard))
                if action == .resume {
                    isHolding = false
                    requiredPitches = []
                    heard = []
                    try? player.play()
                } else {
                    requiredPitches = runner!.remainingPitches(pressed: audio.heardPitches.union(heard))
                }
            }
        }
    }

    private func syncJudge() {
        guard let judge else { return }
        for (id, judgement) in judge.results where results[id] == nil { results[id] = judgement != .missed }
        summary = judge.summary
    }

    /// End of the song (or loop pass): record the pass.
    private func finishPass() {
        guard let judge, judge.judgedCount > 0 || mode == .wait else { return }
        let seconds = Date.now.timeIntervalSince(startedAt)
        let accuracy = mode == .playAlong ? judge.summary.accuracy : 1
        let pass = Result(hits: judge.summary.hits, missed: judge.summary.missed, extras: judge.summary.extras, accuracy: accuracy, seconds: seconds)
        result = pass
        if mode == .playAlong, accuracy > (song.bestAccuracy ?? 0) { song.bestAccuracy = accuracy }
        if logsStandalone { logStandalone(pass) }
        do { try context.save() } catch { ErrorLog.shared.error("Songs", "Couldn't save the pass", error: error) }
        pause()
    }

    private func logStandalone(_ pass: Result) {
        let session = PracticeSession(startedAt: startedAt, goalMinutes: max(UserDefaults.standard.integer(forKey: SettingsKey.dailyGoalMinutes), 20))
        session.duration = pass.seconds
        session.endedAt = .now
        context.insert(session)
        context.insert(block(for: pass, in: session))
    }

    func block(for pass: Result, in session: PracticeSession?) -> PracticeBlock {
        let block = PracticeBlock(kind: RoutineKind.song.rawValue, title: title, startedAt: startedAt)
        block.duration = pass.seconds
        block.attempts = pass.hits + pass.missed
        block.correct = pass.hits
        block.score = pass.accuracy
        block.session = session
        block.song = song
        return block
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
