import App
import ArgumentParser
import Foundation

/// Manages the `himalaya-mcp` entry in Claude Desktop's config.
///
/// Usage:
///   himalaya-mcp setup            # add/update the MCP server entry
///   himalaya-mcp setup --check    # verify the entry is correct
///   himalaya-mcp setup --remove   # remove the entry
struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Add, verify, or remove the himalaya-mcp entry in Claude Desktop's config."
    )

    @Flag(name: .long, help: "Verify the current configuration instead of writing it.")
    var check = false

    @Flag(name: .long, help: "Remove the himalaya-mcp entry.")
    var remove = false

    @Option(name: .long, help: "Path to the Claude Desktop config (defaults to the OS location).")
    var config: String?

    func validate() throws {
        if check, remove {
            throw ValidationError("Use only one of --check or --remove.")
        }
    }

    func run() async throws {
        let setup = ClaudeDesktopSetup(configURL: resolvedConfigURL())

        if check {
            try runCheck(setup)
        } else if remove {
            try runRemove(setup)
        } else {
            try runInstall(setup)
        }
    }

    // MARK: - Modes

    private func runInstall(_ setup: ClaudeDesktopSetup) throws {
        let entry = makeEntry()
        switch try setup.install(entry) {
        case .added:
            print("Added \(ClaudeDesktopSetup.serverName) to \(setup.configURL.path)")
        case .updated:
            print("Updated \(ClaudeDesktopSetup.serverName) in \(setup.configURL.path)")
        default:
            break
        }
        print("  command:  \(entry.command)")
        if let bin = entry.env["HIMALAYA_BIN_PATH"] {
            print("  himalaya: \(bin)")
        }
        print("Restart Claude Desktop for the change to take effect.")
    }

    private func runRemove(_ setup: ClaudeDesktopSetup) throws {
        switch try setup.remove() {
        case .removed:
            print("Removed \(ClaudeDesktopSetup.serverName) from \(setup.configURL.path)")
            print("Restart Claude Desktop for the change to take effect.")
        case .notPresent:
            print("No \(ClaudeDesktopSetup.serverName) entry in \(setup.configURL.path); nothing to remove.")
        default:
            break
        }
    }

    private func runCheck(_ setup: ClaudeDesktopSetup) throws {
        let result = try setup.check()
        print("Config: \(result.configPath)")
        print("  exists:            \(mark(result.configExists))")
        print("  himalaya-mcp entry: \(mark(result.entryPresent))")
        if let command = result.command {
            print("  command:           \(mark(result.commandRunnable)) \(command)")
        }
        if let bin = result.himalayaBinPath {
            print("  HIMALAYA_BIN_PATH: \(mark(result.himalayaRunnable)) \(bin)")
        }
        if result.isHealthy {
            print("OK — configuration looks correct.")
        } else {
            print("Problems:")
            for problem in result.problems {
                print("  - \(problem)")
            }
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    private func resolvedConfigURL() -> URL {
        guard let config else { return ClaudeDesktopSetup.defaultConfigURL() }

        return URL(fileURLWithPath: Self.expandingTilde(config))
    }

    /// Builds the server entry for this machine: the running binary as `command`,
    /// and env that makes himalaya resolvable from Claude Desktop's minimal
    /// environment (GUI apps don't inherit the shell `PATH`).
    private func makeEntry() -> ClaudeDesktopSetup.ServerEntry {
        var env = [
            "HIMALAYA_FOLDER": "INBOX",
            "HIMALAYA_TIMEOUT": "120000"
        ]
        var pathDirs = ["/usr/local/bin", "/usr/bin", "/bin"]

        if let himalaya = try? app.make(HimalayaServiceKey.self).resolveExecutablePath() {
            env["HIMALAYA_BIN_PATH"] = himalaya
            pathDirs.insert(URL(fileURLWithPath: himalaya).deletingLastPathComponent().path, at: 0)
        } else {
            FileHandle.standardError.write(Data(
                "warning: himalaya not found — set HIMALAYA_BIN_PATH manually in the config.\n".utf8
            ))
        }
        env["PATH"] = pathDirs.joined(separator: ":")

        return ClaudeDesktopSetup.ServerEntry(command: Self.selfExecutablePath(), args: ["serve"], env: env)
    }

    /// Absolute path to the running executable (so the entry keeps working
    /// regardless of the invoking shell's PATH).
    private static func selfExecutablePath() -> String {
        let raw = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ClaudeDesktopSetup.serverName
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
    }

    private static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }

        let home = ProcessInfo.processInfo.environment["HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst(1)
    }

    private func mark(_ ok: Bool) -> String {
        ok ? "✓" : "✗"
    }
}
