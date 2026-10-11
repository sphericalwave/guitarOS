import Foundation
import Observation

/// A round of theory flashcards: tap answers, each one grades a `theory` card. No audio.
@Observable
@MainActor
final class TheoryDrillViewModel {
    enum Phase: Equatable {
        case idle
        case asking
        case answered(TheoryDrill.Verdict)
        case finished
    }

    let kind: TheoryDrill.Kind
    let preferSharps: Bool
    private(set) var questions: [TheoryDrill.Question] = []
    private(set) var position = 0
    private(set) var phase: Phase = .idle
    private(set) var correctCount = 0
    private(set) var wrongCount = 0

    let cards: CardStore

    var current: TheoryDrill.Question? { position < questions.count && phase != .finished ? questions[position] : nil }
    var progress: Double { questions.isEmpty ? 0 : Double(position) / Double(questions.count) }

    static let feedbackTime: TimeInterval = 1.0

    @ObservationIgnored private var askedAt = Date.now
    @ObservationIgnored private var advance: Task<Void, Never>?

    init(kind: TheoryDrill.Kind, preferSharps: Bool, cards: CardStore) {
        self.kind = kind
        self.preferSharps = preferSharps
        self.cards = cards
    }

    func start(count: Int = TheoryDrill.questionsPerRound) {
        let due = cards.dueKeys(kind: .theory).filter { $0.hasPrefix("theory:") }
        questions = TheoryDrill.questions(kind: kind, count: count, seed: UInt64(Date.now.timeIntervalSince1970), preferSharps: preferSharps, dueKeys: due)
        position = 0
        correctCount = 0
        wrongCount = 0
        phase = questions.isEmpty ? .finished : .asking
        askedAt = .now
    }

    func stop() {
        advance?.cancel()
        advance = nil
        phase = .idle
        questions = []
    }

    /// A choice index, or a pitch class for note-grid questions.
    func answer(_ choice: Int) {
        guard let question = current, phase == .asking else { return }
        let verdict = TheoryDrill.grade(question, chosen: choice)
        let correct = verdict == .correct
        if correct { correctCount += 1 } else { wrongCount += 1 }
        cards.record(kind: .theory, key: question.key, correct: correct, response: Date.now.timeIntervalSince(askedAt), thresholds: TheoryDrill.thresholds)
        phase = .answered(verdict)
        advance = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.feedbackTime))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    private func next() {
        position += 1
        if position >= questions.count { phase = .finished } else { phase = .asking; askedAt = .now }
    }
}
