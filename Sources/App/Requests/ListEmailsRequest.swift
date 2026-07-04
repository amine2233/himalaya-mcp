import CascadeKit

/// Lists envelopes in a folder via `himalaya envelope list`.
public struct ListEmailsRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Folder to list. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Number of envelopes per page.
        public let pageSize: Int?
        /// 1-based page number.
        public let page: Int?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(folder: String? = nil, pageSize: Int? = nil, page: Int? = nil, account: String? = nil) {
            self.folder = folder
            self.pageSize = pageSize
            self.page = page
            self.account = account
        }

        private enum CodingKeys: String, CodingKey {
            case folder
            case pageSize = "page_size"
            case page
            case account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        var arguments = ["envelope", "list"]
        if let folder = input.folder { arguments += ["--folder", folder] }
        if let pageSize = input.pageSize { arguments += ["--page-size", String(pageSize)] }
        if let page = input.page { arguments += ["--page", String(page)] }
        if let account = input.account { arguments += ["--account", account] }
        return try application.make(HimalayaServiceKey.self).run(arguments: arguments)
    }
}
