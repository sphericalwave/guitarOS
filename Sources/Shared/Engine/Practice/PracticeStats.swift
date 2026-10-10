import Foundation
import SwCharts

/// Totals, streaks and chart samples from sessions. Nothing here is stored: counters conflict across
/// devices, so everything is recomputed from the synced sessions.
nonisolated enum PracticeStats {
    struct Day: Equatable, Sendable {
        var date: Date
        var minutes: Double
    }

    static var calendar: Calendar { PeriodBucketer.standardCalendar() }

    /// Minutes per local day, from session start dates.
    static func dailyMinutes(sessions: [(startedAt: Date, duration: TimeInterval)]) -> [Date: Double] {
        var days: [Date: Double] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            days[day, default: 0] += session.duration / 60
        }
        return days
    }

    /// One sample per session, for `PeriodChartView` (`.sum`).
    static func minuteSamples(sessions: [(startedAt: Date, duration: TimeInterval)]) -> [DatedSample] {
        sessions.map { DatedSample(date: $0.startedAt, value: $0.duration / 60) }
    }

    static func minutes(on day: Date, sessions: [(startedAt: Date, duration: TimeInterval)]) -> Double {
        dailyMinutes(sessions: sessions)[calendar.startOfDay(for: day)] ?? 0
    }

    /// Consecutive days with at least `threshold` minutes, ending today or yesterday (today isn't over).
    static func streak(sessions: [(startedAt: Date, duration: TimeInterval)], now: Date = .now, threshold: Double = 1) -> Int {
        let days = dailyMinutes(sessions: sessions)
        var day = calendar.startOfDay(for: now)
        if (days[day] ?? 0) < threshold {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (days[day] ?? 0) >= threshold {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Heatmap intensity for a day: minutes against the goal, capped at 1.
    static func intensity(minutes: Double, goalMinutes: Int) -> Double {
        guard minutes > 0 else { return 0 }
        return min(1, max(0.15, minutes / Double(max(goalMinutes, 1))))
    }
}
