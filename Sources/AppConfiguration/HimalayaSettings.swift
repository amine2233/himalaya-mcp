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

    public init(account: String? = nil, folder: String? = nil, timeoutMilliseconds: Int = 120_000) {
        self.account = account
        self.folder = folder
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    /// Reads the settings from a configuration reader.
    ///
    /// Each value resolves from its environment variable (e.g. `HIMALAYA_ACCOUNT`)
    /// or the matching dotted key in a config file (e.g. `himalaya.account`).
    public init(config: ConfigReader) {
        self.account = config.string(forKey: "himalaya.account")
        self.folder = config.string(forKey: "himalaya.folder")
        self.timeoutMilliseconds = config.int(forKey: "himalaya.timeout", default: 120_000)
    }
}
