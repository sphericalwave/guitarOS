import SwiftUI
import DiagnosticsKit

struct ToolsView: View {
    var body: some View {
        List {
            Section("Support") {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            }
        }
        .navigationTitle("Tools")
    }
}
