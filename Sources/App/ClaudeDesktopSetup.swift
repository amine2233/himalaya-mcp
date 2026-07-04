import Foundation

/// Manages the `himalaya-mcp` entry inside a Claude Desktop
/// `claude_desktop_config.json`.
///
/// Every operation preserves the rest of the file (other MCP servers, user
/// preferences) — only the `mcpServers.himalaya-mcp` entry is touched. JSON is
/// read/written with `JSONSerialization` so unknown keys survive round-trips.
public struct ClaudeDesktopSetup: Sendable {
    /// Key used for this server under `mcpServers`.
    public static let serverName = "himalaya-mcp"

    /// One server definition written under `mcpServers.<serverName>`.
    public struct ServerEntry: Sendable, Equatable {
        public let command: String
        public let args: [String]
        public let env: [String: String]

        public init(command: String, args: [String], env: [String: String]) {
            self.command = command
            self.args = args
            self.env = env
        }

        var jsonObject: [String: Any] {
            ["command": command, "args": args, "env": env]
        }
    }

    /// Outcome of a mutating operation.
    public enum Outcome: Sendable, Equatable {
        case added
        case updated
        case removed
        case notPresent
    }

    /// Result of `check()`.
    public struct CheckResult: Sendable, Equatable {
        public var configPath: String
        public var configExists: Bool
        public var entryPresent: Bool
        public var command: String?
        public var commandRunnable: Bool
        public var himalayaBinPath: String?
        public var himalayaRunnable: Bool
        public var problems: [String]

        /// No problems detected.
        public var isHealthy: Bool {
            problems.isEmpty
        }
    }

    public let configURL: URL

    public init(configURL: URL) {
        self.configURL = configURL
    }

    /// The default Claude Desktop config path for the current platform.
    public static func defaultConfigURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let home = environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
#if os(macOS)
        return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
#else
        let base = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return base.appendingPathComponent("Claude/claude_desktop_config.json")
#endif
    }

    /// Adds or updates the `himalaya-mcp` entry, preserving all other config.
    @discardableResult
    public func install(_ entry: ServerEntry) throws -> Outcome {
        var root = try loadRoot()
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let existed = servers[Self.serverName] != nil
        servers[Self.serverName] = entry.jsonObject
        root["mcpServers"] = servers
        try save(root)
        return existed ? .updated : .added
    }

    /// Removes the `himalaya-mcp` entry, leaving everything else intact.
    @discardableResult
    public func remove() throws -> Outcome {
        var root = try loadRoot()
        guard var servers = root["mcpServers"] as? [String: Any],
              servers[Self.serverName] != nil else {
            return .notPresent
        }

        servers.removeValue(forKey: Self.serverName)
        root["mcpServers"] = servers
        try save(root)
        return .removed
    }

    /// Inspects the current config and reports whether the entry is healthy.
    public func check() throws -> CheckResult {
        let configExists = FileManager.default.fileExists(atPath: configURL.path)
        let root = try loadRoot()
        let entry = (root["mcpServers"] as? [String: Any])?[Self.serverName] as? [String: Any]

        let command = entry?["command"] as? String
        let himalayaBinPath = (entry?["env"] as? [String: Any])?["HIMALAYA_BIN_PATH"] as? String
        let commandRunnable = command.map(Self.isExecutable) ?? false
        let himalayaRunnable = himalayaBinPath.map(Self.isExecutable) ?? false

        var problems: [String] = []
        if !configExists {
            problems.append("Config file not found at \(configURL.path).")
        }
        if entry == nil {
            problems.append("No \(Self.serverName) entry under mcpServers.")
        } else {
            if command == nil {
                problems.append("Entry has no \"command\".")
            } else if !commandRunnable {
                problems.append("command is not an executable file: \(command ?? "").")
            }
            if let himalayaBinPath, !himalayaRunnable {
                problems.append("HIMALAYA_BIN_PATH is not an executable file: \(himalayaBinPath).")
            }
        }

        return CheckResult(
            configPath: configURL.path,
            configExists: configExists,
            entryPresent: entry != nil,
            command: command,
            commandRunnable: commandRunnable,
            himalayaBinPath: himalayaBinPath,
            himalayaRunnable: himalayaRunnable,
            problems: problems
        )
    }

    // MARK: - JSON I/O

    private func loadRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }

        let data = try Data(contentsOf: configURL)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidArgument("Claude Desktop config is not a JSON object: \(configURL.path)")
        }

        return object
    }

    private func save(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: configURL)
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
