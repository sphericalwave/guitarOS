import Foundation

/// Mirrors the settings that describe the guitar (tuning, reference A) to iCloud key-value storage,
/// so the iPhone and the Mac agree about the instrument. Everything else stays per device.
@MainActor
final class CloudSettings {
    static let mirroredKeys = [SettingsKey.tuning, SettingsKey.referenceA]

    private let defaults: UserDefaults
    private let store: NSUbiquitousKeyValueStore
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, store: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.store = store
    }

    func start() {
        // Cloud wins on launch: a value set on the other device is the newer intent.
        for key in Self.mirroredKeys {
            if let value = store.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.pullChanges(changed) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        })
        store.synchronize()
    }

    private func pullChanges(_ changed: [String]?) {
        for key in changed ?? Self.mirroredKeys where Self.mirroredKeys.contains(key) {
            if let value = store.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    private func push() {
        for key in Self.mirroredKeys {
            let local = defaults.object(forKey: key)
            let remote = store.object(forKey: key)
            if let local, (local as? NSObject) != (remote as? NSObject) { store.set(local, forKey: key) }
        }
    }
}
