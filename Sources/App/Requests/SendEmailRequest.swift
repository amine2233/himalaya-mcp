import CascadeKit

/// Sends a message template via `himalaya template send <template>`.
///
/// Uses `template send` (which compiles the MML template into MIME), matching the
/// templates produced by `compose_email`/`draft_reply`. `message send` would be
/// wrong here — it expects an already-raw RFC 5322 message.
///
/// Sending is irreversible, so this refuses to run unless `confirm` is `true`.
public struct SendEmailRequest: Request {
    public struct Input: Sendable, Decodable {
        /// The raw message/template to send (e.g. from `compose_email` or `draft_reply`).
        public let template: String
        /// Absolute paths of files to attach, appended to the template as MML.
        public let attachments: [String]?
        /// Must be `true` for the send to actually happen.
        public let confirm: Bool?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(
            template: String,
            attachments: [String]? = nil,
            confirm: Bool? = nil,
            account: String? = nil
        ) {
            self.template = template
            self.attachments = attachments
            self.confirm = confirm
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        guard input.confirm == true else {
            return "Refusing to send: set confirm=true to actually send the message."
        }

        let template = MMLAttachment.appended(to: input.template, paths: input.attachments ?? [])
        let output = try application.runHimalaya(
            application.himalayaDialect.sendTemplate(template, account: input.account)
        )
        return output.isEmpty ? "Message sent." : output
    }
}
