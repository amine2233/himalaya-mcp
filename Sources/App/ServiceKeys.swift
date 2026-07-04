import AppConfiguration
import CascadeKit

/// Service key for the resolved feature flags.
public enum FeatureFlagsServiceKey: ServiceKey {
    public typealias Value = FeatureFlags
}
