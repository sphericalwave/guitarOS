import SwiftUI

struct RootView: View {
    @AppStorage("guitarSelectedTab") private var selectedTab = AppSection.today.rawValue

    private var selection: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: selectedTab) ?? .today },
            set: { selectedTab = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack { screen(for: section).toolbar { TunerToolbarButton() } }
                    .tabItem { Label(section.title, systemImage: section.icon) }
                    .tag(section)
            }
        }
    }

    @ViewBuilder
    private func screen(for section: AppSection) -> some View {
        switch section {
        case .practice: PracticeView()
        case .tools: ToolsView()
        default: PlaceholderScreen(section: section)
        }
    }
}
