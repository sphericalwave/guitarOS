import SwiftUI
import DiagnosticsKit

struct ToolsView: View {
    var body: some View {
        List {
            Section("Tools") {
                NavigationLink {
                    TunerView()
                } label: {
                    Label("Tuner", systemImage: "tuningfork")
                }
            }
            Section("Support") {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Tools")
    }
}
