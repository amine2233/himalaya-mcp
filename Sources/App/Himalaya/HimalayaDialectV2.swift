import AppConfiguration

/// himalaya v2 command builder.
///
/// v2 reworks the CLI: `mailbox` replaces `folder`, `--mailbox` replaces
/// `--folder`, `--json` replaces `-o json`, `envelope search` is its own command,
/// flags are passed as `--flag <F>`, `message move` uses `--from`/`--to`, and the
/// `template`/`export`/`message delete` commands are gone. Operations that v2
/// (currently, alpha) doesn't offer throw a clear "not supported" error.
public struct HimalayaDialectV2: HimalayaDialect {
    public let version: HimalayaVersion = .v2

    private let defaultAccount: String?
    private let defaultFolder: String?
    /// Backend used for mailbox management (create/delete), which v2 exposes only
    /// via the backend-specific API (`imap`/`gmail`/`jmap`/`msgraph`). Defaults to
    /// `imap`; override via `HIMALAYA_BACKEND` for other backends.
    private let mailboxBackend: String

    public init(
        defaultAccount: String? = nil,
        defaultFolder: String? = nil,
        mailboxBackend: String = "imap"
    ) {
        self.defaultAccount = defaultAccount
        self.defaultFolder = defaultFolder
        self.mailboxBackend = mailboxBackend
    }

    private func mailboxArgs(_ mailbox: String?) -> [String] {
        (mailbox ?? defaultFolder).map { ["--mailbox", $0] } ?? []
    }

    private func accountArgs(_ account: String?) -> [String] {
        (account ?? defaultAccount).map { ["--account", $0] } ?? []
    }

    public func listEnvelopes(
        mailbox: String?,
        pageSize: Int?,
        page: Int?,
        account: String?
    ) -> HimalayaInvocation {
        var args = ["envelope", "list"] + mailboxArgs(mailbox)
        if let pageSize { args += ["--page-size", String(pageSize)] }
        if let page { args += ["--page", String(page)] }
        return HimalayaInvocation(args + accountArgs(account))
    }

    public func searchEnvelopes(query: String, mailbox: String?, account: String?) -> HimalayaInvocation {
        let args = ["envelope", "search"] + mailboxArgs(mailbox) + accountArgs(account)
        return HimalayaInvocation(args + query.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    public func readMessage(id: String, mailbox: String?, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["message", "read", id] + mailboxArgs(mailbox) + accountArgs(account))
    }

    public func exportMessage(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) throws -> HimalayaInvocation {
        throw unsupported("Exporting a message (read_email_html)")
    }

    public func listMailboxes(account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["mailbox", "list"] + accountArgs(account))
    }

    public func createMailbox(name: String, account: String?) -> HimalayaInvocation {
        // v2 exposes mailbox creation only via the backend API, e.g. `imap create <name>`.
        HimalayaInvocation([mailboxBackend, "create", name] + accountArgs(account))
    }

    public func deleteMailbox(name: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation([mailboxBackend, "delete", name] + accountArgs(account))
    }

    public func setFlags(
        id: String,
        flags: [String],
        add: Bool,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // v2: `flag add|remove --flag <F> ... <MESSAGE-IDS>`
        let flagArgs = flags.flatMap { ["--flag", $0] }
        return HimalayaInvocation(["flag", add ? "add" : "remove"] + flagArgs + [id] + mailboxArgs(mailbox) +
            accountArgs(account))
    }

    public func moveMessage(
        id: String,
        target: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // v2: `message move --to <NAME> [--from <NAME>] <MESSAGE-IDS>`
        var args = ["message", "move", "--to", target]
        if let from = mailbox ?? defaultFolder { args += ["--from", from] }
        return HimalayaInvocation(args + [id] + accountArgs(account))
    }

    public func composeTemplate(
        to: String,
        subject: String,
        body: String,
        account: String?
    ) throws -> HimalayaInvocation {
        throw unsupported("Composing a template (compose_email)")
    }

    public func replyTemplate(
        id: String,
        body: String?,
        all: Bool,
        mailbox: String?,
        account: String?
    ) throws -> HimalayaInvocation {
        throw unsupported("Replying with a template (draft_reply)")
    }

    public func sendTemplate(_ template: String, account: String?) -> HimalayaInvocation {
        // v2 has no `template send`; `message send` reads a raw message from stdin.
        HimalayaInvocation(["message", "send"] + accountArgs(account), standardInput: template)
    }

    public func listAttachments(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(["attachment", "download", id, "--dir", destination] + mailboxArgs(mailbox) +
            accountArgs(account))
    }

    public func downloadAttachments(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(["attachment", "download", id, "--dir", destination] + mailboxArgs(mailbox) +
            accountArgs(account))
    }

    public func deleteMessages(
        ids: [String],
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // v2 has no `message delete`; mark the messages `\Deleted` (batch), which
        // matches v1's mark-as-deleted behaviour (expunge to permanently remove).
        HimalayaInvocation(["flag", "add", "--flag", "Deleted"] + ids + mailboxArgs(mailbox) +
            accountArgs(account))
    }

    public func listAccountsJSON() -> HimalayaInvocation {
        HimalayaInvocation(["account", "list", "--json"])
    }

    public func probeAccount(_ name: String) -> HimalayaInvocation {
        HimalayaInvocation(["mailbox", "list", "--account", name])
    }
}
