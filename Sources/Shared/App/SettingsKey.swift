import Foundation

/// `@AppStorage` keys. Tuning and reference pitch describe the guitar, so they're mirrored to
/// iCloud key-value storage later (M2); everything else is per device.
nonisolated enum SettingsKey {
    static let selectedTab = "guitarSelectedTab"
    static let sidebarPane = "guitarSidebarPane"
    static let leftHanded = "leftHanded"
    /// `Tuning.description`, e.g. "E2 A2 D3 G3 B3 E4".
    static let tuning = "tuning"
    static let preferSharps = "preferSharps"
    static let fretCount = "fretCount"
}
