import CascadeKit

/// Creates a folder via `himalaya folder add <name>`.
public struct CreateFolderRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Name of the folder to create.
        public let name: String
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(name: String, account: String? = nil) {
            self.name = name
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        var arguments = ["folder", "add", input.name]
        if let account = input.account { arguments += ["--account", account] }
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
