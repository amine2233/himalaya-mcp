import CascadeKit
import Foundation

/// Reads the HTML body of a message.
///
/// himalaya's `message read` only renders a plain, human-friendly version, so
/// this uses `message export` — the documented way to "read a HTML message" —
/// exporting every MIME part into a throwaway directory and returning the HTML
/// part's contents. The directory is always cleaned up.
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
        try HimalayaWorkspace.withTemporaryDirectory { directory in
            var arguments = ["message", "export", input.id, "--destination", directory.path]
            if let folder = input.folder { arguments += ["--folder", folder] }
            if let account = input.account { arguments += ["--account", account] }
            _ = try application.make(HimalayaServiceKey.self).run(arguments: arguments)

            guard let html = try Self.htmlContents(in: directory) else {
                return "No HTML part found for message \(input.id)."
            }

            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Returns the concatenated contents of the exported HTML part(s), preferring
    /// files with an `.html`/`.htm` extension and otherwise sniffing for markup.
    private static func htmlContents(in directory: URL) throws -> String? {
        let files = try HimalayaWorkspace.files(in: directory)

        let byExtension = files.filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
        let candidates = byExtension.isEmpty ? files : byExtension

        var matches: [String] = []
        for url in candidates {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            if !byExtension.isEmpty || content.lowercased().contains("<html") {
                matches.append(content)
            }
        }
        return matches.isEmpty ? nil : matches.joined(separator: "\n")
    }
}
