import CascadeKit

/// Generates a reply template via `himalaya message reply <id>`.
///
/// This does **not** send: it returns a quoted reply template. Pass the result
/// to `send_email`.
public struct DraftReplyRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id being replied to.
        public let id: String
        /// Optional body to prefill above the quoted original.
        public let body: String?
        /// Reply to every recipient (`--all`) rather than just the sender.
        public let replyAll: Bool?
        /// Folder the message lives in. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(
            id: String,
            body: String? = nil,
            replyAll: Bool? = nil,
            folder: String? = nil,
            account: String? = nil
        ) {
            self.id = id
            self.body = body
            self.replyAll = replyAll
            self.folder = folder
            self.account = account
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case body
            case replyAll = "reply_all"
            case folder
            case account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        var arguments = ["template", "reply", input.id]
        if input.replyAll == true { arguments.append("--all") }
        if let folder = input.folder { arguments += ["--folder", folder] }
        if let account = input.account { arguments += ["--account", account] }
        if let body = input.body { arguments.append(body) }
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
