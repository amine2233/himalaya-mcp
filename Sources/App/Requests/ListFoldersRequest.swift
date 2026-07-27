
/// Lists all folders via `himalaya folder list`.
public struct ListFoldersRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(account: String? = nil) {
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        try application.runHimalaya(application.himalayaDialect.listMailboxes(account: input.account))
    }
}
