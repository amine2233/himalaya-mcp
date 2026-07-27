
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
        let preprocessed = Self.preprocess(input)
        let compiled = try executable.run(executable: path, arguments: ["compile"], standardInput: preprocessed.template)
        return Self.postprocess(compiled, context: preprocessed.context)
    }

    /// State carried from preprocess to postprocess.
    struct CompileContext {
        let userContentType: String?
    }

    /// All transforms applied before `mml compile`.
    static func preprocess(_ input: String) -> (template: String, context: CompileContext) {
        let sanitized = stripInterTagWhitespace(input)
        let (stripped, ct) = extractContentType(sanitized)
        return (stripped, CompileContext(userContentType: ct))
    }

    /// All transforms applied after `mml compile`.
    static func postprocess(_ compiled: String, context: CompileContext) -> String {
        guard let ct = context.userContentType else { return compiled }
        return reapplyContentType(compiled, userContentType: ct)
    }

    // ponytail: strip Content-Type before mml compile (it truncates the subtype and
    // duplicates it), reapply after. Upgrade: file upstream fix on pimalaya/mml.
    static func extractContentType(_ input: String) -> (stripped: String, contentType: String?) {
        guard let sepRange = input.range(of: "\n\n") else { return (input, nil) }
        let headerBlock = String(input[...sepRange.lowerBound])
        let body = String(input[sepRange.upperBound...])

        let lines = headerBlock.split(separator: "\n", omittingEmptySubsequences: false)
        var contentType: String?
        var filtered: [Substring] = []
        for line in lines {
            if line.lowercased().hasPrefix("content-type:") {
                contentType = String(line.dropFirst("Content-Type:".count)).trimmingCharacters(in: .whitespaces)
            } else {
                filtered.append(line)
            }
        }
        guard let contentType else { return (input, nil) }
        return (filtered.joined(separator: "\n") + "\n" + body, contentType)
    }

    static func reapplyContentType(_ compiled: String, userContentType: String) -> String {
        // ponytail: normalize to \n for splitting (Swift treats \r\n as one Character),
        // rejoin with original separator.
        let hasCRLF = compiled.contains("\r\n")
        let normalized = hasCRLF ? compiled.replacingOccurrences(of: "\r\n", with: "\n") : compiled
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var replaced = false
        var isMultipart = false
        var pastFirstBoundary = false
        for line in lines {
            let lower = line.lowercased()
            if !replaced && lower.hasPrefix("content-type:") && lower.contains("multipart/") {
                isMultipart = true
                result.append(String(line))
                continue
            }
            if isMultipart && line.hasPrefix("--") {
                pastFirstBoundary = true
            }
            if !replaced && lower.hasPrefix("content-type:") {
                if !isMultipart || pastFirstBoundary {
                    result.append("Content-Type: \(userContentType)")
                    replaced = true
                    continue
                }
            }
            result.append(String(line))
        }
        return result.joined(separator: hasCRLF ? "\r\n" : "\n")
    }

    // ponytail: splits headers from body, collapses whitespace between MML structural
    // tags in the body only. Upgrade to a real MML pre-processor if edge cases appear.
    static func stripInterTagWhitespace(_ input: String) -> String {
        guard let separatorRange = input.range(of: "\n\n") else { return input }
        let headers = input[...separatorRange.lowerBound]
        let body = String(input[separatorRange.upperBound...])

        // Collapse whitespace (including newlines) between structural MML tags:
        // after <#multipart...>, before <#/multipart>, between <#/part> and <#part>
        var collapsed = body
        let structuralPatterns = [
            ("(<#multipart[^>]*>)\\s+(<#)", "$1$2"),
            ("(<#/part>)\\s+(<#)", "$1$2"),
            ("(<#/part>)\\s+(<#/multipart>)", "$1$2"),
        ]
        for (pattern, replacement) in structuralPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                collapsed = regex.stringByReplacingMatches(
                    in: collapsed, range: NSRange(collapsed.startIndex..., in: collapsed),
                    withTemplate: replacement
                )
            }
        }

        return headers + "\n" + collapsed
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
