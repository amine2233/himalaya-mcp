
/// Composes an email from structured fields and then, depending on `action`,
/// returns it for review, saves it as a draft, or sends it.
///
/// Uses the `EmailComposer` to build an MML template. How that template becomes
/// MIME depends on the detected `TemplateStrategy`:
/// - `mmlExternal`: compiled by `mml compile` (send goes through `SendTemplateRequest`).
/// - `himalayaBuiltin` (v1 without mml): himalaya's `template send`/`template save`
///   compile it themselves.
/// - `unavailable` (v2 without mml): the message is built in-process by
///   `MIMEBuilder` and sent/saved raw, so `send_email` works without mml.
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
            case to
            case subject
            case body
            case cc
            case bcc
            case from
            case attachments
            case account
            case action
            case bodyType = "body_type"
            case draftFolder = "draft_folder"
            case readReceipt = "read_receipt"
        }
    }

    private let mimeBuilder: MIMEBuilder

    public init(mimeBuilder: MIMEBuilder = MIMEBuilder()) {
        self.mimeBuilder = mimeBuilder
    }

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let composer = application.emailComposer
        let composition = EmailComposition(
            from: input.from,
            to: input.to,
            cc: input.cc,
            bcc: input.bcc,
            subject: input.subject,
            body: input.body,
            bodyType: input.bodyType ?? .plain,
            attachments: input.attachments ?? [],
            readReceipt: input.readReceipt
        )
        let template = composer.compose(composition)
        let strategy = application.make(CapabilitiesKey.self).templateStrategy

        switch input.action ?? .preview {
        case .preview:
            return "Draft (not saved/sent):\n\n\(template)"
        case .draft:
            let folder = input.draftFolder ?? "Drafts"
            let mime: String = switch strategy {
            case .mmlExternal:
                try application.make(MMLServiceKey.self).compile(template)
            case .himalayaBuiltin:
                // v1 `template save` compiles MML itself.
                template
            case .unavailable:
                try mimeBuilder.build(composition)
            }
            let dialect = application.himalayaDialect
            let output = try application.runHimalaya(
                dialect.saveMessage(mime, folder: folder, account: input.account)
            )
            return output.isEmpty ? "Draft saved to \(folder)." : output
        case .send:
            if strategy == .unavailable {
                let mime = try mimeBuilder.build(composition)
                let sendInput = SendMessageRequest.Input(message: mime, account: input.account)
                return try await SendMessageRequest().execute(sendInput, in: application)
            }
            let sendInput = SendTemplateRequest.Input(
                template: template, confirm: true, account: input.account
            )
            return try await SendTemplateRequest().execute(sendInput, in: application)
        }
    }
}
