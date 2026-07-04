import CascadeKit

/// A single runnable command.
///
/// Each conforming type owns its own logic and declares two typed sides:
/// the `Input` it consumes and the `Output` it produces. The same `Input` value
/// is constructed by both surfaces — the CLI from parsed options, the MCP server
/// by decoding tool arguments — so the surfaces cannot drift on what a command accepts.
///
/// `execute` receives the `application` container (Vapor-style) and resolves the
/// services it needs from it (e.g. `application.make(ExecutableServiceKey.self)`).
public protocol Request: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    /// Runs the command with `input`, resolving any services it needs from `application`.
    func execute(_ input: Input, in application: Application) async throws -> Output
}

/// Reusable input for commands that take no arguments.
public struct EmptyInput: Sendable, Decodable {
    public init() {}
}
