import Foundation

/// Reads the HTML body of a message.
///
/// himalaya's plain `message read` only prints HTML when it is the sole text
/// part, so this reads the parsed message (`message read --json`) and returns
/// the decoded HTML part(s).
public struct ReadEmailHtmlRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id of the message to read.
        public let id: String
        /// Folder the message lives in. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(id: String, folder: String? = nil, account: String? = nil) {
            self.id = id
            self.folder = folder
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let output = try application.runHimalaya(
            application.himalayaDialect.readMessageJSON(
                id: input.id,
                mailbox: input.folder,
                account: input.account
            )
        )
        let html = try HimalayaMessageJSON(output).htmlBodies
        guard !html.isEmpty else {
            return "No HTML part found for message \(input.id)."
        }

        return html.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
