import Foundation

/// Downloads a single named attachment from a message.
///
/// himalaya only downloads *all* attachments at once, so this fetches them into
/// a throwaway directory via `himalaya attachment download`, then returns the
/// contents of the file matching `filename` (as text when it decodes as UTF-8,
/// otherwise a size summary).
public struct DownloadAttachmentRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Envelope id whose attachment to download.
        public let id: String
        /// Name of the attachment to return.
        public let filename: String
        /// Folder the message lives in. `nil` lets himalaya use its default (`INBOX`).
        public let folder: String?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(id: String, filename: String, folder: String? = nil, account: String? = nil) {
            self.id = id
            self.filename = filename
            self.folder = folder
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        try HimalayaWorkspace.withTemporaryDirectory { directory in
            _ = try application.runHimalaya(
                application.himalayaDialect.downloadAttachments(
                    id: input.id, destination: directory.path, mailbox: input.folder, account: input.account
                )
            )

            let files = try HimalayaWorkspace.files(in: directory)
            guard let match = files.first(where: { $0.lastPathComponent == input.filename }) else {
                let available = files.map(\.lastPathComponent).joined(separator: ", ")
                throw AppError.invalidArgument(
                    "Attachment \"\(input.filename)\" not found for message \(input.id). Available: \(available.isEmpty ? "none" : available)."
                )
            }

            let data = try Data(contentsOf: match)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "Downloaded binary attachment \"\(input.filename)\" (\(data.count) bytes). Not shown as it is not UTF-8 text."
        }
    }
}
