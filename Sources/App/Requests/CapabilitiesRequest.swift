
/// Returns the detected capabilities: himalaya version, mml presence,
/// and the template strategy. Diagnostic tool for debugging.
public struct CapabilitiesRequest: Request {
    public struct Input: Sendable, Decodable {
        public init() {}
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let caps = application.make(CapabilitiesKey.self)
        var lines = [
            "himalaya_version: \(caps.himalayaVersion)",
            "mml_present: \(caps.mmlPresent)"
        ]
        if let v = caps.mmlVersion { lines.append("mml_version: \(v)") }
        lines.append("template_strategy: \(caps.templateStrategy.rawValue)")
        return lines.joined(separator: "\n")
    }
}
