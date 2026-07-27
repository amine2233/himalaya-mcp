import AppConfiguration
import CascadeKit

/// A single resolved himalaya invocation: the argument list plus optional text
/// to pipe to stdin (e.g. a template for `template send`).
public struct HimalayaInvocation: Sendable, Equatable {
    public var arguments: [String]
    public var standardInput: String?

    public init(_ arguments: [String], standardInput: String? = nil) {
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

/// Builds himalaya command invocations for a specific CLI version.
///
/// This is the seam that isolates every v1-vs-v2 command difference (e.g.
/// `folder` vs `mailbox`, `--folder` vs `--mailbox`, `template send` vs
/// `message send`). Requests depend only on this protocol, so supporting a new
/// version — or fixing a command — is a localized change in one conformer.
///
/// Operations that a version does not support `throw`
/// `AppError.invalidArgument` with a clear message.
public protocol HimalayaDialect: Sendable {
    /// The version this dialect targets.
    var version: HimalayaVersion { get }

    func listEnvelopes(mailbox: String?, pageSize: Int?, page: Int?, account: String?) throws
        -> HimalayaInvocation
    func searchEnvelopes(query: String, mailbox: String?, account: String?) throws -> HimalayaInvocation
    func readMessage(id: String, mailbox: String?, account: String?) throws -> HimalayaInvocation
    func exportMessage(id: String, destination: String, mailbox: String?, account: String?) throws
        -> HimalayaInvocation

    func listMailboxes(account: String?) throws -> HimalayaInvocation
    func createMailbox(name: String, account: String?) throws -> HimalayaInvocation
    func deleteMailbox(name: String, account: String?) throws -> HimalayaInvocation

    func setFlags(id: String, flags: [String], add: Bool, mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func moveMessage(id: String, target: String, mailbox: String?, account: String?) throws
        -> HimalayaInvocation

    /// Composes a message and writes it to stdout (no send/save). `from` may be
    /// nil (on v1 himalaya auto-fills; on v2 it's resolved from per-account config).
    func composeMessage(
        from: String?,
        to: String,
        cc: String?,
        bcc: String?,
        subject: String,
        body: String,
        attachments: [String],
        account: String?
    ) throws -> HimalayaInvocation
    /// Appends an already-composed message (piped via stdin) to `folder`.
    func saveMessage(_ message: String, folder: String, account: String?) throws -> HimalayaInvocation
    func replyTemplate(id: String, body: String?, all: Bool, mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func sendTemplate(_ template: String, account: String?) throws -> HimalayaInvocation

    func listAttachments(id: String, destination: String, mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func downloadAttachments(id: String, destination: String, mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func deleteMessages(ids: [String], mailbox: String?, account: String?) throws -> HimalayaInvocation

    func listAccountsJSON() throws -> HimalayaInvocation
    func probeAccount(_ name: String) throws -> HimalayaInvocation
}

/// Service key used to register/resolve the active `HimalayaDialect`.
public enum HimalayaDialectKey: ServiceKey {
    public typealias Value = any HimalayaDialect
}

extension HimalayaDialect {
    /// Signals that `operation` isn't available on this himalaya version.
    func unsupported(_ operation: String) -> AppError {
        .invalidArgument("\(operation) is not supported on himalaya \(version.rawValue).")
    }
}

extension Container {
    /// The version-specific himalaya command builder.
    public var himalayaDialect: any HimalayaDialect {
        make(HimalayaDialectKey.self)
    }

    /// Runs a resolved himalaya invocation through the `HimalayaService`.
    public func runHimalaya(_ invocation: HimalayaInvocation) throws -> String {
        try make(HimalayaServiceKey.self)
            .run(arguments: invocation.arguments, standardInput: invocation.standardInput)
    }

    /// The email composer for building MML templates from structured input.
    public var emailComposer: any EmailComposer {
        make(EmailComposerKey.self)
    }
}
