import Configuration
import Foundation
import SystemPackage

/// Resolves configuration into `FeatureFlags`.
///
/// Pure resolver: it builds a `ConfigReader` from the environment (highest
/// precedence) layered over an optional JSON config file and returns the flags.
/// Storage/caching is the dependency container's job — this stays free of any
/// DI framework so it can be reused on its own.
public enum ConfigurationLoader {
    /// Default config file name, looked up in the current working directory.
    private static let defaultConfigFileName = "himalaya-mcp.json"

    /// Resolves the feature flags from the environment layered over an optional
    /// JSON config file (env wins). The file provider is asynchronous, hence `async`.
    public static func resolve() async -> FeatureFlags {
        FeatureFlags(config: await configReader())
    }

    /// Resolves both the feature flags and the himalaya settings from a single
    /// configuration reader (avoids reading the config file twice).
    public static func resolveAll() async -> (flags: FeatureFlags, settings: HimalayaSettings) {
        let reader = await configReader()
        return (FeatureFlags(config: reader), HimalayaSettings(config: reader))
    }

    /// Builds a `ConfigReader` from the environment (highest precedence) layered
    /// over an optional JSON config file.
    private static func configReader() async -> ConfigReader {
        var providers: [any ConfigProvider] = [EnvironmentVariablesProvider()]
        if let fileProvider = await jsonFileProvider() {
            providers.append(fileProvider)
        }
        return ConfigReader(providers: providers)
    }

    /// A JSON file provider for `$HIMALAYA_MCP_CONFIG` (or `himalaya-mcp.json` in the
    /// working directory), or `nil` when no readable file is present.
    private static func jsonFileProvider() async -> (any ConfigProvider)? {
        let path = ProcessInfo.processInfo.environment["HIMALAYA_MCP_CONFIG"] ?? defaultConfigFileName
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try await FileProvider<JSONSnapshot>(filePath: FilePath(path))
        } catch {
            // Malformed/unreadable config file: fall back to env-only, and warn on
            // stderr (never stdout — serve mode reserves it for JSON-RPC).
            FileHandle.standardError.write(Data("warning: ignoring config file \(path): \(error)\n".utf8))
            return nil
        }
    }
}
