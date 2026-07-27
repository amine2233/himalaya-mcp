
/// Deletes one or more messages via `himalaya message delete <id…>`.
///
/// Destructive and irreversible, so this is exposed only as an experimental tool.
public struct DeleteEmailRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope ids to delete. Must contain at least one id.
        public let ids: [String]
        /// Folder the messages live in. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(ids: [String], folder: String? = nil, account: String? = nil) {
            self.ids = ids
            self.folder = folder
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let ids = input.ids.filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            throw AppError.invalidArgument("delete_email requires at least one id.")
        }

        let output = try application.runHimalaya(
            application.himalayaDialect.deleteMessages(
                ids: ids,
                mailbox: input.folder,
                account: input.account
            )
        )
        return output.isEmpty ? "Deleted \(ids.count) message(s): \(ids.joined(separator: ", "))." : output
    }
}
