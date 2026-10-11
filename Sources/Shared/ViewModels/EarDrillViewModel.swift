import Foundation
import Observation
import SwiftData
import PitchKit

/// A round of ear training: the tone player asks, the player answers with a button, or plays the phrase back
/// on the guitar and the mic checks it. Each answer grades a card.
@Observable
@MainActor
final class EarDrillViewModel {
    enum Phase: Equatable {
        case idle
        case asking
        case answered(EarDrill.Verdict)
        case finished
    }

    let mode: EarDrill.Mode
    let level: Int
    private(set) var questions: [EarDrill.Question] = []
    private(set) var position = 0
    private(set) var phase: Phase = .idle
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    /// Play-back: pitches heard so far this question.
    private(set) var heard: [UInt8] = []
    private(set) var heardNote: Int?

    let audio: AudioHub
    let tones: TonePlayer
    let cards: CardStore

    var current: EarDrill.Question? { position < questions.count && phase != .finished ? questions[position] : nil }
    var progress: Double { questions.isEmpty ? 0 : Double(position) / Double(questions.count) }
    var isListening: Bool { mode == .playBack && phase == .asking && !tones.isPlaying }

    static let feedbackTime: TimeInterval = 1.0
    static let stableReadings = 2
    /// Play-back: a new note has to differ from the last heard, or come after this much silence.
    static let repeatGap: TimeInterval = 0.35

    @ObservationIgnored private var askedAt = Date.now
    @ObservationIgnored private var stable: [Int] = []
    @ObservationIgnored private var lastHeardAt = Date.distantPast
    @ObservationIgnored private var silentSince: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var advance: Task<Void, Never>?

    init(mode: EarDrill.Mode, level: Int, audio: AudioHub, tones: TonePlayer, cards: CardStore) {
        self.mode = mode
        self.level = level
        self.audio = audio
        self.tones = tones
        self.cards = cards
    }

    func start(count: Int = EarDrill.questionsPerRound) {
        let due = cards.dueKeys(kind: mode.kind).filter { $0.hasPrefix("ear:") }
        questions = EarDrill.questions(mode: mode, level: level, count: count, seed: UInt64(Date.now.timeIntervalSince1970), dueKeys: due)
        position = 0
        correctCount = 0
        wrongCount = 0
        guard !questions.isEmpty else { phase = .finished; return }
        if mode == .playBack {
            audio.acquire()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(40))
                    self?.tick()
                }
            }
        }
        ask()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        advance?.cancel()
        advance = nil
        tones.stop()
        if mode == .playBack, phase != .idle, phase != .finished { audio.release() }
        phase = .idle
        questions = []
    }

    func replay() {
        guard let question = current else { return }
        tones.play(question.pitches, a4: audio.referenceA, spacing: question.spacing)
        heard = []
        stable = []
    }

    func answer(_ choice: Int) {
        guard let question = current, phase == .asking, mode != .playBack else { return }
        settle(EarDrill.grade(question, chosen: choice), for: question)
    }

    func skip() {
        guard phase == .asking else { return }
        next()
    }

    // MARK: Private

    private func ask() {
        guard position < questions.count else {
            phase = .finished
            if mode == .playBack { audio.release(); ticker?.cancel(); ticker = nil }
            return
        }
        phase = .asking
        askedAt = .now
        heard = []
        stable = []
        heardNote = nil
        replay()
    }

    /// Play-back: collects stable notes while the tone isn't sounding; grades when the phrase is long enough.
    private func tick() {
        guard let question = current, phase == .asking, mode == .playBack, !tones.isPlaying else { return }
        guard let pitch = audio.pitch else {
            if silentSince == nil { silentSince = .now }
            stable = []
            if heardNote != nil { heardNote = nil }
            return
        }
        let nearest = PitchMath.note(nearest: pitch.frequency, a4: audio.referenceA)
        if heardNote != nearest.note { heardNote = nearest.note }
        if stable.last == nearest.note { stable.append(nearest.note) } else { stable = [nearest.note] }
        guard stable.count == Self.stableReadings, let note = UInt8(exactly: nearest.note) else { return }
        let isRepeat = heard.last == note && (silentSince.map { Date.now.timeIntervalSince($0) < Self.repeatGap } ?? true)
        silentSince = nil
        guard !isRepeat else { return }
        heard.append(note)
        if heard.count >= question.pitches.count {
            let correct = EarDrill.gradePlayBack(question, heard: heard)
            settle(correct ? .correct : .wrong(chosen: -1), for: question)
        }
    }

    private func settle(_ verdict: EarDrill.Verdict, for question: EarDrill.Question) {
        let response = Date.now.timeIntervalSince(askedAt)
        let correct = verdict == .correct
        if correct { correctCount += 1 } else { wrongCount += 1 }
        cards.record(kind: mode.kind, key: question.key, correct: correct, response: response, thresholds: EarDrill.thresholds)
        phase = .answered(verdict)
        advance = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.feedbackTime))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    private func next() {
        position += 1
        ask()
    }
}
