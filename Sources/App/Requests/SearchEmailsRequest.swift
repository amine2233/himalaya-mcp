
/// Searches envelopes via `himalaya envelope list <query>`.
///
/// himalaya's filter/sort query is a sequence of tokens (e.g. `from alice and
/// subject invoice`), so the incoming `query` string is split on whitespace and
/// each token is passed as a separate positional argument.
public struct SearchEmailsRequest: Request {
    public struct Input: Sendable, Decodable {
        /// himalaya filter/sort query, e.g. `subject invoice order by date desc`.
        public let query: String
        /// Folder to search. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(query: String, folder: String? = nil, account: String? = nil) {
            self.query = query
            self.folder = folder
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        try application.runHimalaya(
            application.himalayaDialect.searchEnvelopes(
                query: input.query, mailbox: input.folder, account: input.account
            )
        )
    }
}
