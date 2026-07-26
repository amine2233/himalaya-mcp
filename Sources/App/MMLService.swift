import CascadeKit
import Foundation

/// Strategy for compiling MML templates into MIME.
public enum TemplateStrategy: String, Sendable {
    /// External `mml compile` binary (preferred, works on both v1 and v2).
    case mmlExternal = "mml_external"
    /// v1's built-in `template send` does its own compilation (no dry_run, MIME may differ).
    case himalayaBuiltin = "himalaya_builtin"
    /// `mml` is absent and v2 cannot compile MML.
    case unavailable
}

/// Detected capabilities, cached for the process lifetime.
public struct Capabilities: Sendable {
    public let himalayaVersion: String
    public let himalayaFamily: HimalayaFamily
    public let mmlPresent: Bool
    public let mmlVersion: String?
    public let templateStrategy: TemplateStrategy
}

/// Which CLI family was detected via structural probe.
public enum HimalayaFamily: String, Sendable {
    case v1
    case v2
}

/// Resolves and runs the `mml` binary.
public protocol MMLService: Sendable {
    func compile(_ input: String) throws -> String
    func isAvailable() -> Bool
    func version() -> String?
}

/// Service key for the `MMLService`.
public enum MMLServiceKey: ServiceKey {
    public typealias Value = any MMLService
}

/// Service key for the cached `Capabilities`.
public enum CapabilitiesKey: ServiceKey {
    public typealias Value = Capabilities
}

/// Live `MMLService` that shells out to the `mml` binary.
public struct MMLServiceDefault: MMLService {
    private let executable: any ExecutableService
    private let mmlPath: String?

    public init(executable: any ExecutableService, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        self.mmlPath = Self.findMML(environment: environment)
    }

    public func compile(_ input: String) throws -> String {
        guard let path = mmlPath else {
            throw AppError.mmlNotFound
        }
        return try executable.run(executable: path, arguments: ["compile"], standardInput: input)
    }

    public func isAvailable() -> Bool { mmlPath != nil }

    public func version() -> String? {
        guard let path = mmlPath else { return nil }
        return try? executable.run(executable: path, arguments: ["--version"])
    }

    private static func findMML(environment: [String: String]) -> String? {
        if let override = environment["MML_BIN_PATH"], !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in directories {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("mml").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
