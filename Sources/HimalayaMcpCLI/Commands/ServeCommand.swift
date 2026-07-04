import ArgumentParser
import MCP

/// MCP surface: runs the application as a Model Context Protocol server over
/// stdio, exposing the same features as MCP tools.
///
/// Usage: `himalaya-mcp serve`
///
/// The server communicates with the host over stdin/stdout using JSON-RPC, so
/// nothing else must be written to stdout while serving. Use stderr for logging.
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run as an MCP server over stdio, exposing features as tools."
    )

    func run() async throws {
        let server = await makeServer(application: app)

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
