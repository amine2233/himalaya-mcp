import CascadeKit
import Foundation

/// Lists a message's attachments.
///
/// himalaya has no "list attachments" command, so this downloads them into a
/// throwaway directory via `himalaya attachment download` and reports the file
/// names and sizes found there.
public struct ListAttachmentsRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id whose attachments to list.
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
        try HimalayaWorkspace.withTemporaryDirectory { directory in
            var arguments = ["attachment", "download", input.id, "--downloads-dir", directory.path]
            if let folder = input.folder { arguments += ["--folder", folder] }
            if let account = input.account { arguments += ["--account", account] }
            _ = try application.make(HimalayaServiceKey.self).run(arguments: arguments)

            let files = try HimalayaWorkspace.files(in: directory)
            guard !files.isEmpty else {
                return "No attachments found for message \(input.id)."
            }
            return files.map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return "\(url.lastPathComponent) (\(size) bytes)"
            }.joined(separator: "\n")
        }
    }
}
