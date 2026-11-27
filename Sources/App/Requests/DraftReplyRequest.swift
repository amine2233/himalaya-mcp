
/// Composes a reply via `himalaya message reply <id>`.
///
/// This does **not** send: it returns the quoted reply. Pass the result
/// to `send_email`.
public struct DraftReplyRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id being replied to.
        public let id: String
        /// Optional body to prefill above the quoted original.
        public let body: String?
        /// Reply to every recipient rather than just the sender: the original
        /// `To`/`Cc` are added as `Cc`, minus the sender and this mailbox's own
        /// address (`Delivered-To`/`X-Original-To`).
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
        let dialect = application.himalayaDialect
        var cc: [String] = []
        if input.replyAll == true {
            let original = try HimalayaMessageJSON(application.runHimalaya(
                dialect.readMessageJSON(id: input.id, mailbox: input.folder, account: input.account)
            ))
            cc = Self.replyAllCc(original)
        }
        return try application.runHimalaya(
            dialect.replyMessage(
                id: input.id, body: input.body, cc: cc, mailbox: input.folder, account: input.account
            )
        )
    }

    /// Original `To` + `Cc`, de-duplicated, without the addresses himalaya
    /// already replies to (`Reply-To`/`From`) nor our own (`Delivered-To`,
    /// `X-Original-To`).
    static func replyAllCc(_ original: HimalayaMessageJSON) -> [String] {
        let excluded = Set(
            ["from", "reply_to", "delivered_to", "X-Original-To"].flatMap { original.addresses(inHeader: $0) }
        )
        var seen = Set<String>()
        return (original.addresses(inHeader: "to") + original.addresses(inHeader: "cc"))
            .filter { !excluded.contains($0) && seen.insert($0).inserted }
    }
}
