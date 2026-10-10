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
    /// Reference A in Hz: 440 (default), 432, or a custom 415...466.
    static let referenceA = "referenceA"
    /// Last custom A the user typed, shown as the field's placeholder.
    static let lastCustomA = "lastCustomA"
    /// `InputProfile` raw value.
    static let inputProfile = "inputProfile"
    static let sensitivity = "sensitivity"
    static let inputMonitoring = "inputMonitoring"
    /// `TunerViewModel.Reference` raw value: which reference control was last chosen.
    static let referenceChoice = "referenceChoice"
    /// `FretboardDrill.Mode` raw value; the trainer remembers the last mode.
    static let drillMode = "drillMode"
    /// JSON `FretboardDrill.Scope`.
    static let drillScope = "drillScope"
}
