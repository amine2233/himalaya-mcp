import AppConfiguration

/// himalaya v2 command builder.
///
/// Targets the himalaya v2 CLI: `mailbox`/`--mailbox`, `--json`, `envelope
/// search`, `--flag <F>`, `message move --from/--to`, and the IMAP-specific
/// `imap create`/`imap delete` for folders. There is no `template` command:
/// MML is compiled by the external `mml` binary, or `send_email` builds MIME
/// natively.
public struct HimalayaDialectV2: HimalayaDialect {
    private let defaultAccount: String?
    private let defaultFolder: String?

    public init(defaultAccount: String? = nil, defaultFolder: String? = nil) {
        self.defaultAccount = defaultAccount
        self.defaultFolder = defaultFolder
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

    public func readMessageJSON(id: String, mailbox: String?, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["message", "read", id] + mailboxArgs(mailbox) + accountArgs(account) + ["--json"])
    }

    public func listMailboxes(account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["mailbox", "list"] + accountArgs(account))
    }

    public func createMailbox(name: String, account: String?) -> HimalayaInvocation {
        // v2's shared `mailbox` API only lists; creation is IMAP-specific.
        HimalayaInvocation(["imap", "create", name] + accountArgs(account))
    }

    public func deleteMailbox(name: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["imap", "delete", name] + accountArgs(account))
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

    public func composeMessage(
        from: String?,
        to: String,
        cc: String?,
        bcc: String?,
        subject: String,
        body: String,
        attachments: [String],
        account: String?
    ) -> HimalayaInvocation {
        // v2: `message compose` writes RFC 5322 to stdout; native `--attach`.
        var args = ["message", "compose", "--to", to, "--subject", subject, "--body", body]
        if let from { args += ["--from", from] }
        if let cc { args += ["--cc", cc] }
        if let bcc { args += ["--bcc", bcc] }
        for path in attachments {
            args += ["--attach", path]
        }
        return HimalayaInvocation(args + accountArgs(account))
    }

    public func saveMessage(_ message: String, folder: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(
            ["message", "save", "--mailbox", folder] + accountArgs(account),
            standardInput: message
        )
    }

    public func replyMessage(
        id: String,
        body: String?,
        cc: [String],
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // Without --save/--send, `message reply` prints the composed reply. Always
        // pass --body so himalaya never waits on stdin.
        var args = ["message", "reply", id] + mailboxArgs(mailbox) + accountArgs(account)
        args += ["--body", body ?? ""]
        if !cc.isEmpty { args += ["--cc", cc.joined(separator: ",")] }
        return HimalayaInvocation(args)
    }

    public func sendTemplate(_ template: String, account: String?) -> HimalayaInvocation {
        // v2 has no `template send`; `message send` reads a raw message from stdin.
        HimalayaInvocation(["message", "send"] + accountArgs(account), standardInput: template)
    }

    public func sendMessage(_ message: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["message", "send"] + accountArgs(account), standardInput: message)
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

    public func deleteMessages(ids: [String], mailbox: String?, account: String?) -> HimalayaInvocation {
        // Moves to the trash, or deletes for good when already in the trash.
        HimalayaInvocation(["message", "delete"] + ids + mailboxArgs(mailbox) + accountArgs(account))
    }

    public func listAccountsJSON() -> HimalayaInvocation {
        HimalayaInvocation(["account", "list", "--json"])
    }

    public func probeAccount(_ name: String) -> HimalayaInvocation {
        HimalayaInvocation(["mailbox", "list", "--account", name])
    }
}
