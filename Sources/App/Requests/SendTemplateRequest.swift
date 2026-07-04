import CascadeKit
import Foundation

/// Sends a himalaya template you author yourself via `himalaya template send`.
///
/// A template is a raw message where the body may use himalaya's MML (e.g.
/// `<#part filename="...">`); `template send` compiles it into a MIME message
/// before sending. Provide the template inline (`template`) or from a file
/// (`templateFile`). Sending is irreversible, so `confirm` must be `true`.
public struct SendTemplateRequest: Request {
    public struct Input: Sendable, Decodable {
        /// The template text (headers + MML body). Mutually exclusive with `templateFile`.
        public let template: String?
        /// Path to a file containing the template. Mutually exclusive with `template`.
        public let templateFile: String?
        /// Absolute paths of files to attach, appended to the template as MML.
        public let attachments: [String]?
        /// Must be `true` for the send to actually happen.
        public let confirm: Bool?
        /// Account override. `nil` uses the configured default account.
        public let account: String?

        public init(
            template: String? = nil,
            templateFile: String? = nil,
            attachments: [String]? = nil,
            confirm: Bool? = nil,
            account: String? = nil
        ) {
            self.template = template
            self.templateFile = templateFile
            self.attachments = attachments
            self.confirm = confirm
            self.account = account
        }

        private enum CodingKeys: String, CodingKey {
            case template
            case templateFile = "template_file"
            case attachments
            case confirm
            case account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let source = try resolveTemplate(input)

        guard input.confirm == true else {
            return "Refusing to send: set confirm=true to actually send the template."
        }

        let template = MMLAttachment.appended(to: source, paths: input.attachments ?? [])
        var arguments = ["template", "send"]
        if let account = input.account { arguments += ["--account", account] }

        // himalaya reads the template from stdin, not from an argument.
        let output = try application.make(HimalayaServiceKey.self)
            .run(arguments: arguments, standardInput: template)
        return output.isEmpty ? "Template sent." : output
    }

    /// Resolves the template text from either the inline value or the file path.
    private func resolveTemplate(_ input: Input) throws -> String {
        switch (input.template, input.templateFile) {
        case let (.some(template), nil):
            return template
        case let (nil, .some(path)):
            do {
                return try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                throw AppError.invalidArgument("Could not read template file \"\(path)\": \(error).")
            }
        case (.some, .some):
            throw AppError.invalidArgument("Provide only one of \"template\" or \"template_file\".")
        case (nil, nil):
            throw AppError.invalidArgument("Provide a \"template\" or \"template_file\" to send.")
        }
    }
}
