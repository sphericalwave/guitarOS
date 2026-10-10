import Foundation
import Observation
import PitchKit

/// One sitting of the fretboard note trainer. The queue is fixed when it starts; the mic (or a tap)
/// grades each prompt, the card store reschedules it, and the next prompt comes up on its own.
@Observable
@MainActor
final class FretboardDrillViewModel {
    enum Phase: Equatable {
        case idle
        case asking
        case answered(FretboardDrill.Verdict)
        case finished
    }

    private(set) var queue: [FretboardDrill.Prompt] = []
    private(set) var position = 0
    private(set) var phase: Phase = .idle
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    /// The note the mic hears right now, for the live readout.
    private(set) var heardNote: Int?

    var mode: FretboardDrill.Mode
    let fretboard: Fretboard
    let audio: AudioHub
    private let cards: CardStore

    var current: FretboardDrill.Prompt? { position < queue.count && phase != .finished ? queue[position] : nil }
    var progress: Double { queue.isEmpty ? 0 : Double(position) / Double(queue.count) }
    var isListening: Bool { mode == .findTheNote && phase == .asking }

    /// Ignore mic readings for this long after a prompt appears: the previous note is still ringing.
    static let settleTime: TimeInterval = 0.35
    /// How long the verdict shows before the next prompt.
    static let feedbackTime: TimeInterval = 0.9

    @ObservationIgnored private var askedAt = Date.now
    @ObservationIgnored private var stable: [Int] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var advance: Task<Void, Never>?

    init(fretboard: Fretboard, mode: FretboardDrill.Mode, audio: AudioHub, cards: CardStore) {
        self.fretboard = fretboard
        self.mode = mode
        self.audio = audio
        self.cards = cards
    }

    func start(scope: FretboardDrill.Scope, count: Int = 12) {
        queue = FretboardDrill.queue(
            fretboard: fretboard, scope: scope,
            dueKeys: cards.dueKeys(kind: .fretPosition),
            seenKeys: cards.seenKeys(kind: .fretPosition),
            count: count
        )
        position = 0
        correctCount = 0
        wrongCount = 0
        guard !queue.isEmpty else { phase = .finished; return }
        if mode == .findTheNote {
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
        if mode == .findTheNote, phase != .idle, phase != .finished || ticker != nil { audio.release() }
        phase = .idle
        queue = []
    }

    /// Silent mode: the player names the dot.
    func answer(pitchClass: Int) {
        guard let prompt = current, phase == .asking else { return }
        settle(FretboardDrill.judge(prompt: prompt, tappedPitchClass: pitchClass), for: prompt)
    }

    func skip() {
        guard phase == .asking else { return }
        next()
    }

    // MARK: Private

    private func ask() {
        guard position < queue.count else {
            phase = .finished
            if mode == .findTheNote { audio.release(); ticker?.cancel(); ticker = nil }
            return
        }
        phase = .asking
        askedAt = .now
        stable = []
        heardNote = nil
    }

    /// Polls the hub's pitch (20–25 Hz). A note has to hold for a few readings before it's judged.
    private func tick() {
        guard let prompt = current, phase == .asking, mode == .findTheNote else { return }
        guard let pitch = audio.pitch else {
            stable = []
            if heardNote != nil { heardNote = nil }
            return
        }
        let nearest = PitchMath.note(nearest: pitch.frequency, a4: audio.referenceA)
        if heardNote != nearest.note { heardNote = nearest.note }
        guard Date.now.timeIntervalSince(askedAt) > Self.settleTime else { return }
        if stable.last == nearest.note { stable.append(nearest.note) } else { stable = [nearest.note] }
        guard stable.count >= FretboardDrill.stableReadings else { return }
        settle(FretboardDrill.judge(prompt: prompt, heardFrequency: pitch.frequency, referenceA: audio.referenceA), for: prompt)
    }

    private func settle(_ verdict: FretboardDrill.Verdict, for prompt: FretboardDrill.Prompt) {
        let response = Date.now.timeIntervalSince(askedAt)
        let correct = verdict == .correct
        if correct { correctCount += 1 } else { wrongCount += 1 }
        cards.record(
            kind: .fretPosition,
            key: FretboardDrill.cardKey(position: prompt.position, tuning: fretboard.tuning),
            correct: correct,
            response: response,
            thresholds: mode == .findTheNote ? .fretPosition : .nameTheNote
        )
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
