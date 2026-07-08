/// Per-account default `From` addresses, resolved lazily by account name.
///
/// swift-configuration can't enumerate accounts, but it can read a
/// dynamically-built key when the account name is known. This wraps that lookup
/// so the dialects can ask "what is `<account>`'s From address?" without
/// depending on `ConfigReader` directly.
///
/// The address is read from `himalaya.accounts.<account>.from`, which maps to the
/// environment variable `HIMALAYA_ACCOUNTS_<ACCOUNT>_FROM`.
public struct AccountFromNames: Sendable {
    private let fromLookup: @Sendable (String) -> String?

    public init(from: @escaping @Sendable (String) -> String?) {
        self.fromLookup = from
    }

    /// The configured From address for `account`, or `nil` when none is set.
    public func from(forAccount account: String) -> String? {
        fromLookup(account)
    }

    /// A resolver with no overrides (every account resolves to `nil`).
    public static let none = AccountFromNames { _ in nil }
}
