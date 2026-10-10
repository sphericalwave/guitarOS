import SwiftUI

/// iOS presents the tuner as a sheet; no extra scene is needed, so this is a placeholder window
/// group that is never opened (the Mac uses a real utility window).
struct TunerScene: Scene {
    let audio: AudioHub

    var body: some Scene {
        WindowGroup("Tuner", id: "tuner") { EmptyView() }
    }
}
