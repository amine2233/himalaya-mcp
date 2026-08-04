
/// Sends a raw RFC 5322 message verbatim (no MML compilation).
///
/// Validates the message has a header/body separator, normalizes line endings
/// to CRLF, and pipes it to the dialect's send command via stdin.
public struct SendMessageRequest: Request {
    public struct Input: Sendable, Decodable {
        public let message: String
        public let account: String?
        public let dryRun: Bool?

        public init(message: String, account: String? = nil, dryRun: Bool? = nil) {
            self.message = message
            self.account = account
            self.dryRun = dryRun
        }

        private enum CodingKeys: String, CodingKey {
            case message
            case account
            case dryRun = "dry_run"
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let normalized = normalizeCRLF(input.message)
        try validateHeaderBodySeparator(normalized)

        if input.dryRun == true {
            return "dry_run: true\nwould_send_to: \(input.account ?? "default")\n\n\(normalized)"
        }

        let dialect = application.himalayaDialect
        let invocation = try dialect.sendTemplate(normalized, account: input.account)
        let output = try application.runHimalaya(invocation)
        let id = parseMessageId(output)
        return id.map { "sent: true\nid: \($0)" } ?? "sent: true"
    }
}

/// Normalize lone `\n` to `\r\n` without doubling existing `\r\n`.
func normalizeCRLF(_ input: String) -> String {
    // ponytail: simple two-pass replacement, regex if edge cases appear
    input
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n", with: "\r\n")
}

/// Validates presence of a blank line separating headers from body.
func validateHeaderBodySeparator(_ message: String) throws {
    guard message.contains("\r\n\r\n") || message.contains("\n\n") else {
        throw AppError.missingHeaderBodySeparator
    }
}

/// Tolerant id parser — extracts a message id from himalaya's stdout if present.
func parseMessageId(_ output: String) -> String? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return trimmed
}
