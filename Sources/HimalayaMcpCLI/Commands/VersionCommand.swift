import ArgumentParser

/// Release version of this CLI. Rewritten by `bumpversion.sh` at release time —
/// keep the `let appVersion = "…"` shape on a single line so `sed` can match it.
let appVersion = "1.0.0"

/// Prints the release version.
///
/// Usage:
///   himalaya-mcp version
struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the release version of this CLI."
    )

    func run() {
        print(appVersion)
    }
}
