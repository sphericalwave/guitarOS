import SwiftUI
import SwiftData
import DiagnosticsKit
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

    /// SwiftData + CloudKit. If the cloud store can't open (no iCloud account, container not provisioned)
    /// the same file is opened locally. Never wipes a store on failure: a crash is better than lost data.
    let container: ModelContainer = {
        let schema = Schema([SkillCard.self])
        if let cloud = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)]) {
            return cloud
        }
        ErrorLog.shared.warning("Store", "CloudKit unavailable; using the local store")
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)])
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }()

    init() {
        cloudSettings.start()
        CardStore(context: container.mainContext).dedupe()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(audio)
        }
        .modelContainer(container)
        TunerScene(audio: audio)
    }
}
