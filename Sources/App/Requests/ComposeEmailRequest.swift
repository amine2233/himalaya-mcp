import CascadeKit

/// Composes a new message template via `himalaya message write`.
///
/// This does **not** send: it returns a ready-to-send template (headers + body,
/// with attachments expressed as MML). Pass the result to `send_email`.
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
        var arguments = [
            "message", "write",
            "--header", "To:\(input.to)",
            "--header", "Subject:\(input.subject)"
        ]
        if let account = input.account { arguments += ["--account", account] }
        arguments.append(body)
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
