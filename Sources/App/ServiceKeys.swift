import AppConfiguration
import CascadeKit

/// Service key for the resolved feature flags.
public enum FeatureFlagsServiceKey: ServiceKey {
    public typealias Value = FeatureFlags
}

/// Service key for the resolved himalaya settings (default account/folder, timeout).
public enum HimalayaSettingsServiceKey: ServiceKey {
    public typealias Value = HimalayaSettings
}
