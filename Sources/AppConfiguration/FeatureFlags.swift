import Configuration

/// Feature flags resolved from configuration.
///
/// Plain `Sendable` data so any consumer (CLI, MCP server, future tools) can read
/// the same resolved flags synchronously.
public struct FeatureFlags: Sendable {
    /// When true, experimental CLI subcommands and MCP tools are exposed.
    public let experimentalEnabled: Bool

    public init(experimentalEnabled: Bool) {
        self.experimentalEnabled = experimentalEnabled
    }

    /// Reads the flags from a configuration reader.
    ///
    /// `experimental.enabled` resolves from `EXPERIMENTAL_ENABLED` (environment)
    /// or `experimental.enabled` in a config file, defaulting to `false`.
    public init(config: ConfigReader) {
        self.experimentalEnabled = config.bool(forKey: "experimental.enabled", default: false)
    }
}
