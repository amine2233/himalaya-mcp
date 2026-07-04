import Configuration
import Foundation
import SystemPackage

/// Resolves configuration into `FeatureFlags` and `HimalayaSettings`.
///
/// Precedence (highest first):
///   1. Environment variables — always win over any file.
///   2. The first readable config file found among, in order:
///        - `$HIMALAYA_MCP_CONFIG` (explicit override), else `himalaya-mcp.json`
///          in the current working directory   ← highest-priority file
///        - `$XDG_CONFIG_HOME/himalaya-mcp/config.json`
///        - `$HOME/.config/himalaya-mcp/config.yml`
///        - `$HOME/.himalayamcprc`
///
/// The parser is chosen by file extension: `.yaml`/`.yml` → YAML, everything else
/// (`.json`, `.himalayamcprc`, …) → JSON.
///
/// Pure resolver: it builds a `ConfigReader` and returns the resolved values.
/// Storage/caching is the dependency container's job — this stays free of any DI
/// framework so it can be reused on its own.
public enum ConfigurationLoader {
    /// Config file name looked up in the current working directory (highest-priority file).
    private static let defaultConfigFileName = "himalaya-mcp.json"

    /// Resolves the feature flags from the environment layered over an optional
    /// config file (env wins). The file provider is asynchronous, hence `async`.
    public static func resolve() async -> FeatureFlags {
        await FeatureFlags(config: configReader())
    }

    /// Resolves both the feature flags and the himalaya settings from a single
    /// configuration reader (avoids reading the config file twice).
    public static func resolveAll() async -> (flags: FeatureFlags, settings: HimalayaSettings) {
        let reader = await configReader()
        return (FeatureFlags(config: reader), HimalayaSettings(config: reader))
    }

    /// Builds a `ConfigReader` from the environment (highest precedence) layered
    /// over the first readable config file found on the search path.
    private static func configReader() async -> ConfigReader {
        var providers: [any ConfigProvider] = [EnvironmentVariablesProvider()]
        if let fileProvider = await fileProvider() {
            providers.append(fileProvider)
        }
        return ConfigReader(providers: providers)
    }

    /// The ordered config-file search path. The current-directory file (or the
    /// `$HIMALAYA_MCP_CONFIG` override) comes first; then the XDG/home locations.
    static func candidatePaths(environment: [String: String] = ProcessInfo.processInfo
        .environment) -> [String] {
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let xdg = environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"

        var paths: [String] = []
        if let explicit = environment["HIMALAYA_MCP_CONFIG"], !explicit.isEmpty {
            paths.append(explicit)
        }
        paths.append(defaultConfigFileName)
        paths.append("\(xdg)/himalaya-mcp/config.json")
        paths.append("\(home)/.config/himalaya-mcp/config.yml")
        paths.append("\(home)/.himalayamcprc")
        return paths
    }

    /// The first readable config file on the search path, parsed into a provider,
    /// or `nil` when none exists. A file that exists but fails to parse is warned
    /// about and skipped, so the next candidate is tried.
    private static func fileProvider() async -> (any ConfigProvider)? {
        for path in candidatePaths() {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            do {
                return try await makeProvider(path: path)
            } catch {
                // Never write to stdout — serve mode reserves it for JSON-RPC.
                FileHandle.standardError.write(Data("warning: ignoring config file \(path): \(error)\n".utf8))
            }
        }
        return nil
    }

    /// Selects the snapshot format by file extension.
    private static func makeProvider(path: String) async throws -> any ConfigProvider {
        let filePath = FilePath(path)
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "yaml", "yml":
            return try await FileProvider<YAMLSnapshot>(filePath: filePath)
        default:
            return try await FileProvider<JSONSnapshot>(filePath: filePath)
        }
    }
}
