
/// Content type for the email body.
public enum EmailBodyType: String, Sendable, Decodable {
    case plain
    case html
}

/// Structured input for composing an email as an MML template.
public struct EmailComposition: Sendable {
    public let from: String?
    public let to: String
    public let cc: String?
    public let bcc: String?
    public let subject: String
    public let body: String
    public let bodyType: EmailBodyType
    public let attachments: [String]
    /// Email address for read receipt (Disposition-Notification-To, RFC 8098).
    public let readReceipt: String?

    public init(
        from: String? = nil,
        to: String,
        cc: String? = nil,
        bcc: String? = nil,
        subject: String,
        body: String,
        bodyType: EmailBodyType = .plain,
        attachments: [String] = [],
        readReceipt: String? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.bodyType = bodyType
        self.attachments = attachments
        self.readReceipt = readReceipt
    }
}

/// Builds MML templates from structured input. Never emits a Content-Type
/// header — lets `mml compile` handle MIME typing (avoids HIMA-15).
public protocol EmailComposer: Sendable {
    func compose(_ input: EmailComposition) -> String
}

public enum EmailComposerKey: ServiceKey {
    public typealias Value = any EmailComposer
}

/// Default composer: builds RFC 5322 headers + MML body.
public struct EmailComposerDefault: EmailComposer {
    public init() {}

    public func compose(_ input: EmailComposition) -> String {
        var headers: [String] = []
        if let from = input.from { headers.append("From: \(from)") }
        headers.append("To: \(input.to)")
        if let cc = input.cc { headers.append("Cc: \(cc)") }
        if let bcc = input.bcc { headers.append("Bcc: \(bcc)") }
        headers.append("Subject: \(input.subject)")
        if let addr = input.readReceipt { headers.append("Disposition-Notification-To: \(addr)") }

        let body: String = switch input.bodyType {
        case .plain:
            input.body
        case .html:
            "<#part type=text/html>\(input.body)<#/part>"
        }

        let withAttachments = MMLAttachment.appended(to: body, paths: input.attachments)
        return headers.joined(separator: "\n") + "\n\n" + withAttachments
    }
}
