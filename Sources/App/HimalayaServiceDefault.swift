import Foundation

/// Live `HimalayaService`.
///
/// Locates the `himalaya` binary once per invocation using a two-step strategy:
///
/// 1. **Override** — if `HIMALAYA_BIN_PATH` is set, that path is used (and must
///    point at an executable file, else resolution fails). It always wins.
/// 2. **`PATH` search** — otherwise each directory in `PATH` is probed, in order,
///    for an executable named `himalaya`; the first hit wins.
///
/// Once resolved, the command is delegated to the injected `ExecutableService`,
/// so the process-running machinery stays in one place and is stubbable in tests.
///
/// Before delegating, configured defaults are woven into the arguments: a default
/// `--account` (for any command, when none was given) and a default `--folder`
/// (for commands that accept one, when none was given).
public struct HimalayaServiceDefault: HimalayaService {
    /// Name of the executable searched for on `PATH`.
    public static let executableName = "himalaya"

    /// Environment variable that, when set, overrides `PATH` discovery with an
    /// explicit absolute path to the `himalaya` binary.
    public static let pathOverrideEnvironmentKey = "HIMALAYA_BIN_PATH"

    private let executable: any ExecutableService
    private let environment: [String: String]
    private let defaultAccount: String?
    private let defaultFolder: String?

    /// - Parameters:
    ///   - executable: Runner used to spawn the resolved binary.
    ///   - environment: Environment to read the override and `PATH` from. Defaults
    ///     to the current process environment.
    ///   - defaultAccount: Account injected as `--account` when a call omits one.
    ///   - defaultFolder: Folder injected as `--folder` when a folder-accepting
    ///     call omits one.
    public init(
        executable: any ExecutableService,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultAccount: String? = nil,
        defaultFolder: String? = nil
    ) {
        self.executable = executable
        self.environment = environment
        self.defaultAccount = defaultAccount
        self.defaultFolder = defaultFolder
    }

    public func resolveExecutablePath() throws -> String {
        // 1. Explicit override always wins; if set it must be valid.
        if let override = environment[Self.pathOverrideEnvironmentKey], !override.isEmpty {
            guard Self.isExecutableFile(atPath: override) else {
                throw AppError.himalayaExecutableNotFound(searchedPaths: [override])
            }

            return override
        }

        // 2. Search each PATH directory in order for an executable `himalaya`.
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var searched: [String] = []
        for directory in directories {
            let candidate = Self.join(directory: directory, name: Self.executableName)
            searched.append(candidate)
            if Self.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw AppError.himalayaExecutableNotFound(searchedPaths: searched)
    }

    public func run(arguments: [String]) throws -> String {
        let effective = Self.applyingDefaults(to: arguments, account: defaultAccount, folder: defaultFolder)
        return try executable.run(executable: resolveExecutablePath(), arguments: effective)
    }

    /// Weaves the configured default account/folder into `arguments`, leaving an
    /// explicitly-provided `--account`/`--folder` untouched.
    static func applyingDefaults(to arguments: [String], account: String?, folder: String?) -> [String] {
        var arguments = arguments
        if let account, !arguments.contains("--account") {
            arguments += ["--account", account]
        }
        if let folder, commandAcceptsFolder(arguments), !arguments.contains("--folder") {
            arguments += ["--folder", folder]
        }
        return arguments
    }

    /// Whether the himalaya command in `arguments` accepts a `--folder` option.
    /// The `folder` subcommands and `message write`/`message send` do not.
    static func commandAcceptsFolder(_ arguments: [String]) -> Bool {
        switch arguments.first {
        case "folder":
            return false
        case "message":
            let subcommand = arguments.dropFirst().first
            return subcommand != "write" && subcommand != "send"
        default:
            return arguments.first != nil
        }
    }

    /// Whether `path` points at a runnable file. Wraps `FileManager` so the
    /// filesystem probe lives in one place.
    private static func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Joins a directory and file name into a path. Uses `URL` rather than
    /// `NSString` so it behaves identically on macOS and Linux.
    private static func join(directory: String, name: String) -> String {
        URL(fileURLWithPath: directory).appendingPathComponent(name).path
    }
}
