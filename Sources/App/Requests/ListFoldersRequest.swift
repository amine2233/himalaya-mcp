import CascadeKit

/// Lists all folders via `himalaya folder list`.
public struct ListFoldersRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(account: String? = nil) {
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        var arguments = ["folder", "list"]
        if let account = input.account { arguments += ["--account", account] }
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
