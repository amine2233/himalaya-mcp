
/// Moves a message to another folder via `himalaya message move <target> <id>`.
public struct MoveEmailRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id to move.
        public let id: String
        /// Destination folder.
        public let targetFolder: String
        /// Source folder. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(id: String, targetFolder: String, folder: String? = nil, account: String? = nil) {
            self.id = id
            self.targetFolder = targetFolder
            self.folder = folder
            self.account = account
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case targetFolder = "target_folder"
            case folder
            case account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        try application.runHimalaya(
            application.himalayaDialect.moveMessage(
                id: input.id, target: input.targetFolder, mailbox: input.folder, account: input.account
            )
        )
    }
}
