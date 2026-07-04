import Configuration

/// Runtime defaults for driving the himalaya CLI, resolved from configuration.
///
/// Plain `Sendable` data so any consumer (services, requests) can read the same
/// resolved values synchronously.
public struct HimalayaSettings: Sendable {
    /// Default account, used when a call doesn't specify one. `nil` means fall
    /// back to himalaya's own default account. (`HIMALAYA_ACCOUNT`)
    public let account: String?

    /// Default folder, used when a call doesn't specify one. `nil` means fall
    /// back to himalaya's own default (`INBOX`). (`HIMALAYA_FOLDER`)
    public let folder: String?

    /// Command timeout in milliseconds. `0` means no timeout. (`HIMALAYA_TIMEOUT`,
    /// default `120000` = 2 minutes)
    public let timeoutMilliseconds: Int

    /// Which himalaya CLI major version to target. (`HIMALAYA_VERSION`, default `v1`)
    public let version: HimalayaVersion

    /// Backend used for v2 mailbox management (create/delete), which v2 exposes
    /// only per-backend. `nil` means the dialect's default (`imap`).
    /// (`HIMALAYA_BACKEND`)
    public let backend: String?

    public init(
        account: String? = nil,
        folder: String? = nil,
        timeoutMilliseconds: Int = 120_000,
        version: HimalayaVersion = .v1,
        backend: String? = nil
    ) {
        self.account = account
        self.folder = folder
        self.timeoutMilliseconds = timeoutMilliseconds
        self.version = version
        self.backend = backend
    }

    /// Reads the settings from a configuration reader.
    ///
    /// Each value resolves from its environment variable (e.g. `HIMALAYA_ACCOUNT`)
    /// or the matching dotted key in a config file (e.g. `himalaya.account`).
    public init(config: ConfigReader) {
        self.account = config.string(forKey: "himalaya.account")
        self.folder = config.string(forKey: "himalaya.folder")
        self.timeoutMilliseconds = config.int(forKey: "himalaya.timeout", default: 120_000)
        self.version = HimalayaVersion(string: config.string(forKey: "himalaya.version"))
        self.backend = config.string(forKey: "himalaya.backend")
    }
}
