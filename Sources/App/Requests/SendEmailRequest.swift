import CascadeKit

/// Composes an email from structured fields and then, depending on `action`,
/// returns it for review, saves it as a draft, or sends it.
///
/// This unifies the former `compose_email` (preview) and `send_email` (send), and
/// adds a real **draft** (saved to the Drafts mailbox). The message is always
/// composed first (`composeMessage`), then:
/// - `.preview` → return the composed message (nothing saved/sent);
/// - `.draft`   → append it to the Drafts mailbox (`saveMessage`);
/// - `.send`    → send it (`sendTemplate`), which is irreversible.
public struct SendEmailRequest: Request {
    /// What to do with the composed message.
    public enum Action: String, Sendable, Decodable {
        case preview
        case draft
        case send
    }

    public struct Input: Sendable, Decodable {
        public let to: String
        public let subject: String
        public let body: String
        public let cc: String?
        public let bcc: String?
        /// Sender address. `nil` falls back to the per-account default
        /// (`HIMALAYA_ACCOUNTS_<NAME>_FROM`); on v1 himalaya auto-fills it.
        public let from: String?
        /// Absolute paths of files to attach.
        public let attachments: [String]?
        /// Account override. `nil` uses the configured default account.
        public let account: String?
        /// `preview` (default), `draft`, or `send`.
        public let action: Action?
        /// Mailbox to save drafts into. Defaults to `Drafts`.
        public let draftFolder: String?

        public init(
            to: String,
            subject: String,
            body: String,
            cc: String? = nil,
            bcc: String? = nil,
            from: String? = nil,
            attachments: [String]? = nil,
            account: String? = nil,
            action: Action? = nil,
            draftFolder: String? = nil
        ) {
            self.to = to
            self.subject = subject
            self.body = body
            self.cc = cc
            self.bcc = bcc
            self.from = from
            self.attachments = attachments
            self.account = account
            self.action = action
            self.draftFolder = draftFolder
        }

        private enum CodingKeys: String, CodingKey {
            case to
            case subject
            case body
            case cc
            case bcc
            case from
            case attachments
            case account
            case action
            case draftFolder = "draft_folder"
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let dialect = application.himalayaDialect
        let composed = try application.runHimalaya(
            dialect.composeMessage(
                from: input.from,
                to: input.to,
                cc: input.cc,
                bcc: input.bcc,
                subject: input.subject,
                body: input.body,
                attachments: input.attachments ?? [],
                account: input.account
            )
        )

        switch input.action ?? .preview {
        case .preview:
            return "Draft (not saved/sent):\n\n\(composed)"
        case .draft:
            let folder = input.draftFolder ?? "Drafts"
            let output = try application.runHimalaya(
                dialect.saveMessage(composed, folder: folder, account: input.account)
            )
            return output.isEmpty ? "Draft saved to \(folder)." : output
        case .send:
            let output = try application.runHimalaya(
                dialect.sendTemplate(composed, account: input.account)
            )
            return output.isEmpty ? "Message sent." : output
        }
    }
}
