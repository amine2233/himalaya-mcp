import CascadeKit

/// Runs external executables. Requests resolve this from the application
/// container via `make`, so the live process runner can be swapped for a stub.
public protocol ExecutableService: Sendable {
    /// Runs an executable resolved from `PATH` and returns its combined,
    /// trimmed standard output and standard error.
    func run(executable: String, arguments: [String]) throws -> String
}

/// Service key used to register/resolve the `ExecutableService` in a container.
public enum ExecutableServiceKey: ServiceKey {
    public typealias Value = any ExecutableService
}
