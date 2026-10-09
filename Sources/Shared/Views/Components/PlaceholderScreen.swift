import SwiftUI

/// Stand-in for a section that isn't built yet. Replaced milestone by milestone.
struct PlaceholderScreen: View {
    let section: AppSection

    var body: some View {
        ContentUnavailableView(section.title, systemImage: section.icon, description: Text("Coming soon."))
            .navigationTitle(section.title)
    }
}
