/// Which major version of the himalaya CLI to target.
///
/// v1 and v2 have materially different command surfaces (e.g. `folder` vs
/// `mailbox`, `--folder` vs `--mailbox`, `-o json` vs `--json`), so the dialect
/// that builds command arguments is selected from this value.
public enum HimalayaVersion: String, Sendable, CaseIterable {
    case v1
    case v2

    /// Parses `"1"`, `"v1"`, `"2"`, `"v2"` (case-insensitive). Defaults to `.v1`
    /// for anything unrecognised or empty.
    public init(string: String?) {
        switch string?.lowercased() {
        case "2", "v2": self = .v2
        default: self = .v1
        }
    }
}
