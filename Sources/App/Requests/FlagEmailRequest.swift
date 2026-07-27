
/// Adds or removes flags on a message via `himalaya flag add|remove <id> <flags…>`.
public struct FlagEmailRequest: Request {
    /// Whether to add or remove the given flags.
    public enum Action: String, Sendable, Decodable {
        case add
        case remove
    }

    public struct Input: Sendable, Decodable {
        /// Envelope id to flag.
        public let id: String
        /// Space-separated flag names (e.g. `Seen`, `Flagged`, `Answered`).
        public let flags: String
        /// Whether to add or remove the flags.
        public let action: Action
        /// Folder the message lives in. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?

        public init(id: String, flags: String, action: Action, folder: String? = nil) {
            self.id = id
            self.flags = flags
            self.action = action
            self.folder = folder
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let flags = input.flags.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !flags.isEmpty else {
            throw AppError.invalidArgument("flag_email requires at least one flag.")
        }

        return try application.runHimalaya(
            application.himalayaDialect.setFlags(
                id: input.id, flags: flags, add: input.action == .add, mailbox: input.folder, account: nil
            )
        )
    }
}
