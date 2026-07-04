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
}

extension AppError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .himalayaExecutableNotFound(let searchedPaths):
            let locations = searchedPaths.isEmpty
                ? "no candidates (PATH is empty)"
                : searchedPaths.joined(separator: ", ")
            return """
            himalaya executable not found. Set \(HimalayaServiceDefault.pathOverrideEnvironmentKey) \
            to its absolute path, or add it to PATH (searched: \(locations)).
            """
        case .invalidArgument(let reason):
            return reason
        }
    }
}
