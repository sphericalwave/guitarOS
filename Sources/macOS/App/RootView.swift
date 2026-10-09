import SwiftUI

struct RootView: View {
    @AppStorage("guitarSidebarPane") private var paneRaw = AppSection.today.rawValue

    private var selection: Binding<AppSection?> {
        Binding(
            get: { AppSection(rawValue: paneRaw) ?? .today },
            set: { if let pane = $0 { paneRaw = pane.rawValue } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            NavigationStack { screen(for: AppSection(rawValue: paneRaw) ?? .today) }
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
