/// Per-account folder-name overrides, resolved lazily by account name.
///
/// swift-configuration can't enumerate the configured accounts, but it can read a
/// dynamically-built key when the account name is known. This wraps that lookup so
/// the dialects can ask "what is `<account>`'s inbox called?" without depending on
/// `ConfigReader` directly.
///
/// The inbox name is read from `himalaya.accounts.<account>.inbox-name`, which maps
/// to the environment variable `HIMALAYA_ACCOUNTS_<ACCOUNT>_INBOX_NAME`.
public struct AccountFolderNames: Sendable {
    private let inboxLookup: @Sendable (String) -> String?

    public init(inbox: @escaping @Sendable (String) -> String?) {
        self.inboxLookup = inbox
    }

    /// The configured inbox mailbox name for `account`, or `nil` when none is set.
    public func inbox(forAccount account: String) -> String? {
        inboxLookup(account)
    }

    /// A resolver with no overrides (every account resolves to `nil`).
    public static let none = AccountFolderNames { _ in nil }
}
