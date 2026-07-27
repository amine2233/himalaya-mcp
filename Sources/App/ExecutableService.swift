
/// Runs external executables. Requests resolve this from the application
/// container via `make`, so the live process runner can be swapped for a stub.
public protocol ExecutableService: Sendable {
    /// Runs an executable resolved from `PATH` and returns its combined,
    /// trimmed standard output and standard error.
    ///
    /// - Parameter standardInput: text piped to the process's stdin (himalaya's
    ///   `template send` reads its input there). `nil` sends no input.
    func run(executable: String, arguments: [String], standardInput: String?) throws -> String
}

extension ExecutableService {
    /// Convenience for the common case of running with no standard input.
    public func run(executable: String, arguments: [String]) throws -> String {
        try run(executable: executable, arguments: arguments, standardInput: nil)
    }
}

/// Service key used to register/resolve the `ExecutableService` in a container.
public enum ExecutableServiceKey: ServiceKey {
    public typealias Value = any ExecutableService
}
