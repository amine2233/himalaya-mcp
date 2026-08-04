import Foundation

/// Compiles an MML template via `mml compile` then sends the resulting MIME.
///
/// This is NOT a parallel code path — it's `send_message` preceded by a
/// compilation step. The `mml` binary is the sole compiler on both v1 and v2.
/// Never sends uncompiled MML as a fallback (that's the original bug).
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
        /// If true, return compiled MIME without sending.
        public let dryRun: Bool?

        public init(
            template: String? = nil,
            templateFile: String? = nil,
            attachments: [String]? = nil,
            confirm: Bool? = nil,
            account: String? = nil,
            dryRun: Bool? = nil
        ) {
            self.template = template
            self.templateFile = templateFile
            self.attachments = attachments
            self.confirm = confirm
            self.account = account
            self.dryRun = dryRun
        }

        private enum CodingKeys: String, CodingKey {
            case template
            case templateFile = "template_file"
            case attachments
            case confirm
            case account
            case dryRun = "dry_run"
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> String {
        let source = try resolveTemplate(input)
        let caps = application.make(CapabilitiesKey.self)

        switch caps.templateStrategy {
        case .mmlExternal:
            let template = MMLAttachment.appended(to: source, paths: input.attachments ?? [])
            let mml = application.make(MMLServiceKey.self)
            let mime: String
            do {
                mime = try mml.compile(template)
            } catch let error as AppError {
                throw error
            } catch {
                throw AppError.mmlCompilationFailed(stderr: error.localizedDescription)
            }

            if input.dryRun == true {
                return "dry_run: true\nstrategy: mml_external\nwould_send_to: \(input.account ?? "default")\n\n\(mime)"
            }

            guard input.confirm == true else {
                return "Refusing to send: set confirm=true to actually send the template."
            }

            let sendInput = SendMessageRequest.Input(message: mime, account: input.account)
            return try await SendMessageRequest().execute(sendInput, in: application)

        case .himalayaBuiltin:
            // ponytail: degraded v1 path without mml — no dry_run, MIME may differ
            if input.dryRun == true {
                throw AppError.invalidArgument("dry_run is unavailable without the mml binary.")
            }
            guard input.confirm == true else {
                return "Refusing to send: set confirm=true to actually send the template."
            }

            let template = MMLAttachment.appended(to: source, paths: input.attachments ?? [])
            let output = try application.runHimalaya(
                application.himalayaDialect.sendTemplate(template, account: input.account)
            )
            return output.isEmpty ? "Template sent." : output

        case .unavailable:
            throw AppError.mmlNotFound
        }
    }

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
