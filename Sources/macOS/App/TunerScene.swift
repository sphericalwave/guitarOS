import SwiftUI

/// The tuner's utility window, opened from the toolbar tuning fork (⌘T).
struct TunerScene: Scene {
    let audio: AudioHub

    var body: some Scene {
        Window("Tuner", id: "tuner") {
            TunerView().environment(audio)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 640)
    }
}
