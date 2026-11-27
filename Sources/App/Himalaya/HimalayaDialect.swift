import AppConfiguration

/// A single resolved himalaya invocation: the argument list plus optional text
/// to pipe to stdin (e.g. a raw message for `message send`).
public struct HimalayaInvocation: Sendable, Equatable {
    public var arguments: [String]
    public var standardInput: String?

    public init(_ arguments: [String], standardInput: String? = nil) {
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

/// Builds himalaya (v2) command invocations.
///
/// Requests depend only on this protocol, so fixing a command is a localized
/// change in `HimalayaDialectV2`, and tests can stub the command surface.
public protocol HimalayaDialect: Sendable {
    func listEnvelopes(mailbox: String?, pageSize: Int?, page: Int?, account: String?) throws
        -> HimalayaInvocation
    func searchEnvelopes(query: String, mailbox: String?, account: String?) throws -> HimalayaInvocation
    func readMessage(id: String, mailbox: String?, account: String?) throws -> HimalayaInvocation
    /// Reads a message as himalaya's parsed JSON (`message read --json`): headers
    /// plus decoded `parts`, with `html_body`/`text_body` indexing into them.
    func readMessageJSON(id: String, mailbox: String?, account: String?) throws -> HimalayaInvocation

    func listMailboxes(account: String?) throws -> HimalayaInvocation
    func createMailbox(name: String, account: String?) throws -> HimalayaInvocation
    func deleteMailbox(name: String, account: String?) throws -> HimalayaInvocation

    func setFlags(id: String, flags: [String], add: Bool, mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func moveMessage(id: String, target: String, mailbox: String?, account: String?) throws
        -> HimalayaInvocation

    /// Composes a message and writes it to stdout (no send/save). `from` may be
    /// nil (resolved from per-account config).
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
    /// Composes a reply to `id` and prints it (no send/save). `cc` adds
    /// carbon-copy recipients (used to implement reply-all).
    func replyMessage(id: String, body: String?, cc: [String], mailbox: String?, account: String?) throws
        -> HimalayaInvocation
    func sendTemplate(_ template: String, account: String?) throws -> HimalayaInvocation
    /// Sends an already-composed raw RFC 5322 message (piped via stdin) verbatim,
    /// with no MML compilation.
    func sendMessage(_ message: String, account: String?) throws -> HimalayaInvocation

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

extension Container {
    /// The himalaya command builder.
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
