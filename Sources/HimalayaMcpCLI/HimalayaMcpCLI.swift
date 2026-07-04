import App
import ArgumentParser
import CascadeKit

/// Root command.
///
/// This single executable can be used two ways:
///
/// * As a plain CLI — subcommands run and print to stdout.
/// * As an MCP server — `himalaya-mcp serve` speaks the Model Context Protocol over
///   stdio so an MCP host (Claude, an IDE, …) can call the same features as tools.
///
/// Both share the same `Application` core, so there is one implementation per
/// feature and two ways to reach it.
struct HimalayaMcpCLI: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "himalaya-mcp",
            abstract: "A himalaya helper usable both as a CLI and as an MCP server.",
            version: "0.1.0",
            subcommands: [
                ServeCommand.self,
                SetupCommand.self,
                DoctorCommand.self
            ],
            defaultSubcommand: ServeCommand.self
        )
    }
}
