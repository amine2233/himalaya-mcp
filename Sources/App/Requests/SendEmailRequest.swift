
/// Composes an email from structured fields and then, depending on `action`,
/// returns it for review, saves it as a draft, or sends it.
///
/// Uses the `EmailComposer` to build an MML template, then compiles it via
/// `mml compile` (through `SendTemplateRequest`) for the send path.
public struct SendEmailRequest: Request {
    public enum Action: String, Sendable, Decodable {
        case preview
        case draft
        case send
    }

    public struct Input: Sendable, Decodable {
        public let to: String
        public let subject: String
        public let body: String
        public let bodyType: EmailBodyType?
        public let cc: String?
        public let bcc: String?
        public let from: String?
        public let attachments: [String]?
        public let account: String?
        public let action: Action?
        public let draftFolder: String?
        public let readReceipt: String?

        public init(
            to: String,
            subject: String,
            body: String,
            bodyType: EmailBodyType? = nil,
            cc: String? = nil,
            bcc: String? = nil,
            from: String? = nil,
            attachments: [String]? = nil,
            account: String? = nil,
            action: Action? = nil,
            draftFolder: String? = nil,
            readReceipt: String? = nil
        ) {
            self.to = to
            self.subject = subject
            self.body = body
            self.bodyType = bodyType
            self.cc = cc
            self.bcc = bcc
            self.from = from
            self.attachments = attachments
            self.account = account
            self.action = action
            self.draftFolder = draftFolder
            self.readReceipt = readReceipt
        }

        private enum CodingKeys: String, CodingKey {
            case to, subject, body, cc, bcc, from, attachments, account, action
            case bodyType = "body_type"
            case draftFolder = "draft_folder"
            case readReceipt = "read_receipt"
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let composer = application.emailComposer
        let template = composer.compose(EmailComposition(
            from: input.from,
            to: input.to,
            cc: input.cc,
            bcc: input.bcc,
            subject: input.subject,
            body: input.body,
            bodyType: input.bodyType ?? .plain,
            attachments: input.attachments ?? [],
            readReceipt: input.readReceipt
        ))

        switch input.action ?? .preview {
        case .preview:
            return "Draft (not saved/sent):\n\n\(template)"
        case .draft:
            let folder = input.draftFolder ?? "Drafts"
            let mml = application.make(MMLServiceKey.self)
            let mime = try mml.compile(template)
            let dialect = application.himalayaDialect
            let output = try application.runHimalaya(
                dialect.saveMessage(mime, folder: folder, account: input.account)
            )
            return output.isEmpty ? "Draft saved to \(folder)." : output
        case .send:
            let sendInput = SendTemplateRequest.Input(
                template: template, confirm: true, account: input.account
            )
            return try await SendTemplateRequest().execute(sendInput, in: application)
        }
    }
}
