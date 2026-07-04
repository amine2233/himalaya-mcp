import App
import ArgumentParser

/// Process entry point.
///
/// Configures dependencies *before* handing control to `swift-argument-parser`,
/// because the root command's `configuration` (which decides whether experimental
/// subcommands exist) is read synchronously during parsing. `configure(_:)` is
/// async (it resolves the config file), so we await it here, then run the command.
@main
struct Main {
    static func main() async {
        await configure(app)
        await HimalayaMcpCLI.main()
    }
}
