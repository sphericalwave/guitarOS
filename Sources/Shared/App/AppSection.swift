import Foundation

/// The four top-level sections: tabs on iOS, sidebar rows on macOS.
/// Raw values are persisted (`@AppStorage`), so keep them stable.
nonisolated enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case today, practice, progress, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .practice: "Practice"
        case .progress: "Progress"
        case .tools: "Tools"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .practice: "guitars"
        case .progress: "chart.bar"
        case .tools: "tuningfork"
        }
    }
}
