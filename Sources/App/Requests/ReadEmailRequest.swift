import CascadeKit

/// Reads the plain-text, human-friendly body of a message via
/// `himalaya message read <id> --no-headers`.
public struct ReadEmailRequest: Request {
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
        var arguments = ["message", "read", input.id, "--no-headers"]
        if let folder = input.folder { arguments += ["--folder", folder] }
        if let account = input.account { arguments += ["--account", account] }
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
