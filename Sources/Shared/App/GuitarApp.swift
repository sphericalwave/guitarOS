import SwiftUI
import PitchKit

@main
struct GuitarApp: App {
    /// Composition root: the one place that knows both the shared services and the platform adapters.
    @State private var audio = AudioHub(
        session: PlatformAudioRecordingSession(),
        inputs: PlatformAudioInputs(),
        referenceA: UserDefaults.standard.object(forKey: SettingsKey.referenceA) as? Double ?? ReferencePitch.standard,
        inputProfile: InputProfile(rawValue: UserDefaults.standard.string(forKey: SettingsKey.inputProfile) ?? "") ?? .unpluggedElectric,
        monitorInput: UserDefaults.standard.bool(forKey: SettingsKey.inputMonitoring)
    )
    private let cloudSettings = CloudSettings()

    init() {
        cloudSettings.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(audio)
        }
        TunerScene(audio: audio)
    }
}
