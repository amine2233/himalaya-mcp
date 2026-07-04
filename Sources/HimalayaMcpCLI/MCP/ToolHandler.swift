import App
import AppConfiguration
import CascadeKit
import Foundation
import MCP

/// Bridges a strongly-typed `Request` to the string-keyed, text-returning world
/// of MCP `tools/call`.
///
/// A `Request` has an `associatedtype`, so a heterogeneous list of them can't be
/// dispatched uniformly. Each `ToolHandler` erases one command into a closure
/// that decodes its typed `Input` from the call arguments, runs it, and returns
/// text — the small, explicit cost of the protocol approach.
struct ToolHandler: Sendable {
    let tool: Tool
    /// Whether this tool is gated behind the experimental feature flag.
    let isExperimental: Bool
    let call: @Sendable (CallTool.Parameters, Application) async throws -> String

    init(
        tool: Tool,
        isExperimental: Bool = false,
        call: @escaping @Sendable (CallTool.Parameters, Application) async throws -> String
    ) {
        self.tool = tool
        self.isExperimental = isExperimental
        self.call = call
    }
}

extension ToolHandler {
    /// Every tool the server knows about, before experimental gating.
    /// Add himalaya `ToolHandler`s here to expose them over MCP.
    static let all: [ToolHandler] = []

    /// The tools visible for the given flags: experimental tools are hidden
    /// unless the experimental feature flag is enabled.
    static func visible(featureFlags: FeatureFlags) -> [ToolHandler] {
        all.filter { !$0.isExperimental || featureFlags.experimentalEnabled }
    }
}

/// Decodes MCP call arguments (`[String: Value]`) into a `Decodable` request
/// input by round-tripping through JSON — `Value` is `Codable`, so a missing
/// argument bag decodes the same as an empty object.
func decodeArguments<T: Decodable>(_ type: T.Type, from arguments: [String: Value]?) throws -> T {
    let data = try JSONEncoder().encode(arguments ?? [:])
    return try JSONDecoder().decode(T.self, from: data)
}
