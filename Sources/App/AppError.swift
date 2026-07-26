/// The single error type for the `App` module.
///
/// Per the module convention, all failures raised by `App` are expressed as
/// cases of this enum so callers have one exhaustive type to switch over.
public enum AppError: Error, Equatable, Sendable {
    /// The `himalaya` executable could not be located, neither through the
    /// `HIMALAYA_BIN_PATH` override nor anywhere on `PATH`. `searchedPaths`
    /// lists every candidate that was probed, for a diagnosable message.
    case himalayaExecutableNotFound(searchedPaths: [String])
    /// A request was given an argument it can't act on (e.g. an unknown flag
    /// action). `reason` explains what was wrong.
    case invalidArgument(String)
    /// A himalaya command ran longer than the configured timeout and was
    /// terminated. `milliseconds` is the limit that was exceeded.
    case commandTimedOut(milliseconds: Int)
    /// The `mml` binary is not installed. Required for `send_template`.
    case mmlNotFound
    /// MML compilation failed. `stderr` contains the full ariadne parse report.
    case mmlCompilationFailed(stderr: String)
    /// The raw message is missing the blank line separating headers from body.
    case missingHeaderBodySeparator
    /// A subprocess exited with a non-zero status.
    case commandFailed(exitCode: Int32, output: String)
}

extension AppError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .himalayaExecutableNotFound(searchedPaths):
            let locations = searchedPaths.isEmpty
                ? "no candidates (PATH is empty)"
                : searchedPaths.joined(separator: ", ")
            return """
            himalaya executable not found. Set \(HimalayaServiceDefault.pathOverrideEnvironmentKey) \
            to its absolute path, or add it to PATH (searched: \(locations)).
            """
        case let .invalidArgument(reason):
            return reason
        case let .commandTimedOut(milliseconds):
            return "himalaya command timed out after \(milliseconds) ms."
        case .mmlNotFound:
            return """
            The mml binary is required for send_template but was not found. \
            Install it with: cargo install mime-meta-language --locked --features cli \
            (crate name is "mime-meta-language", binary is "mml", --features cli is mandatory).
            """
        case let .mmlCompilationFailed(stderr):
            return "MML compilation failed: \(stderr)"
        case .missingHeaderBodySeparator:
            return "Invalid message: missing blank line between headers and body."
        case let .commandFailed(exitCode, output):
            return "Command failed (exit \(exitCode)): \(output)"
        }
    }
}
