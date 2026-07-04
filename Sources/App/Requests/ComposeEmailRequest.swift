import CascadeKit

/// Composes a new message template via `himalaya template write`.
///
/// Uses the `template` family (not `message write`, which launches an editor):
/// it returns a ready-to-send template (headers + body, with attachments
/// expressed as MML) to stdout, and does **not** send. Pass the result to `send_email`.
public struct ComposeEmailRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Recipient address.
        public let to: String
        /// Subject line.
        public let subject: String
        /// Plain-text body.
        public let body: String
        /// Absolute paths of files to attach.
        public let attachments: [String]?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(
            to: String,
            subject: String,
            body: String,
            attachments: [String]? = nil,
            account: String? = nil
        ) {
            self.to = to
            self.subject = subject
            self.body = body
            self.attachments = attachments
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let body = MMLAttachment.appended(to: input.body, paths: input.attachments ?? [])
        return try application.runHimalaya(
            application.himalayaDialect.composeTemplate(
                to: input.to, subject: input.subject, body: body, account: input.account
            )
        )
    }
}
