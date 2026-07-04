import App
import CascadeKit
import MCP

/// Builds an MCP `Server` that exposes `ApplicationCore`'s `Request` commands as
/// tools, driven by a registry of `ToolHandler`s.
///
/// Handlers are registered before the server is returned (and before it is
/// started in `ServeCommand`), so there is no race between startup and the host
/// listing or calling tools. To add a tool, add a `ToolHandler` to `handlers`.
func makeServer(application: Application) async -> Server {
    let server = Server(
        name: "himalaya-mcp",
        version: "0.1.0",
        capabilities: .init(
            tools: .init(listChanged: false)
        )
    )

    // Experimental tools are hidden (and thus unknown if called) unless enabled.
    let handlers = ToolHandler.visible(featureFlags: application.make(FeatureFlagsServiceKey.self))
    let handlersByName = Dictionary(uniqueKeysWithValues: handlers.map { ($0.tool.name, $0) })

    // tools/list — advertise the available tools to the host.
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: handlers.map(\.tool))
    }

    // tools/call — dispatch a tool invocation to its handler.
    await server.withMethodHandler(CallTool.self) { params in
        guard let handler = handlersByName[params.name] else {
            return .init(
                content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        let output = try await handler.call(params, application)
        return .init(
            content: [.text(text: output, annotations: nil, _meta: nil)],
            isError: false
        )
    }

    return server
}
