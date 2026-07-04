import CascadeKit

/// The single entry point for driving the [himalaya](https://github.com/pimalaya/himalaya)
/// CLI. Every himalaya invocation in the app funnels through `run(arguments:)`,
/// so binary resolution (env override, then `PATH` search) lives in one place.
///
/// Requests resolve this from the application container via `make`, so the live
/// runner can be swapped for a stub in tests.
public protocol HimalayaService: Sendable {
    /// Resolves the absolute path to the `himalaya` executable, honouring the
    /// `HIMALAYA_BIN_PATH` override first and falling back to a `PATH` search.
    ///
    /// - Throws: `AppError.himalayaExecutableNotFound` when no executable is found.
    func resolveExecutablePath() throws -> String

    /// Runs `himalaya` with `arguments` and returns its combined, trimmed
    /// standard output and standard error.
    ///
    /// - Parameter standardInput: text piped to himalaya's stdin (required by
    ///   `template send`, which reads the template there). `nil` sends nothing.
    /// - Throws: `AppError.himalayaExecutableNotFound` if the binary can't be
    ///   located, or any error thrown while running the subprocess.
    func run(arguments: [String], standardInput: String?) throws -> String
}

extension HimalayaService {
    /// Convenience for running with no standard input.
    public func run(arguments: [String]) throws -> String {
        try run(arguments: arguments, standardInput: nil)
    }
}

/// Service key used to register/resolve the `HimalayaService` in a container.
public enum HimalayaServiceKey: ServiceKey {
    public typealias Value = any HimalayaService
}
