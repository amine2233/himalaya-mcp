import AppConfiguration

/// himalaya v1 command builder (the default).
///
/// v1 uses the `folder` command family, `--folder` for the mailbox, `-o json`
/// for JSON output, `envelope list <query>` for search, and the `template`
/// family for composing/sending.
public struct HimalayaDialectV1: HimalayaDialect {
    public let version: HimalayaVersion = .v1

    private let defaultAccount: String?
    private let defaultFolder: String?
    private let accountFolders: AccountFolderNames

    public init(
        defaultAccount: String? = nil,
        defaultFolder: String? = nil,
        accountFolders: AccountFolderNames = .none
    ) {
        self.defaultAccount = defaultAccount
        self.defaultFolder = defaultFolder
        self.accountFolders = accountFolders
    }

    /// The effective mailbox: an explicit request folder wins; otherwise the
    /// per-account inbox (for the effective account); otherwise the global default.
    private func resolvedMailbox(_ mailbox: String?, account: String?) -> String? {
        if let mailbox { return mailbox }
        if let account = account ?? defaultAccount,
           let inbox = accountFolders.inbox(forAccount: account) {
            return inbox
        }
        return defaultFolder
    }

    private func folderArgs(_ mailbox: String?, account: String?) -> [String] {
        resolvedMailbox(mailbox, account: account).map { ["--folder", $0] } ?? []
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
        var args = ["envelope", "list"] + folderArgs(mailbox, account: account)
        if let pageSize { args += ["--page-size", String(pageSize)] }
        if let page { args += ["--page", String(page)] }
        return HimalayaInvocation(args + accountArgs(account))
    }

    public func searchEnvelopes(query: String, mailbox: String?, account: String?) -> HimalayaInvocation {
        let args = ["envelope", "list"] + folderArgs(mailbox, account: account) + accountArgs(account)
        return HimalayaInvocation(args + query.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    public func readMessage(id: String, mailbox: String?, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["message", "read", id, "--no-headers"] + folderArgs(mailbox, account: account) +
            accountArgs(account))
    }

    public func exportMessage(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(
            ["message", "export", id, "--destination", destination] + folderArgs(mailbox, account: account) +
                accountArgs(account)
        )
    }

    public func listMailboxes(account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["folder", "list"] + accountArgs(account))
    }

    public func createMailbox(name: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["folder", "add", name] + accountArgs(account))
    }

    public func deleteMailbox(name: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["folder", "delete", name] + accountArgs(account))
    }

    public func setFlags(
        id: String,
        flags: [String],
        add: Bool,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(["flag", add ? "add" : "remove", id] + flags + folderArgs(
            mailbox,
            account: account
        ) +
            accountArgs(account))
    }

    public func moveMessage(
        id: String,
        target: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // v1: `message move <TARGET> <ID>` — target before id.
        HimalayaInvocation(["message", "move", target, id] + folderArgs(mailbox, account: account) +
            accountArgs(account))
    }

    public func composeTemplate(
        to: String,
        subject: String,
        body: String,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(
            ["template", "write", "--header", "To:\(to)", "--header", "Subject:\(subject)"] +
                accountArgs(account) + [body]
        )
    }

    public func replyTemplate(
        id: String,
        body: String?,
        all: Bool,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        var args = ["template", "reply", id]
        if all { args.append("--all") }
        args += folderArgs(mailbox, account: account) + accountArgs(account)
        if let body { args.append(body) }
        return HimalayaInvocation(args)
    }

    public func sendTemplate(_ template: String, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["template", "send"] + accountArgs(account), standardInput: template)
    }

    public func listAttachments(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        // v1 has no `attachment list`; download to a temp dir and inspect it.
        HimalayaInvocation(
            ["attachment", "download", id, "--downloads-dir", destination] + folderArgs(
                mailbox,
                account: account
            ) +
                accountArgs(account)
        )
    }

    public func downloadAttachments(
        id: String,
        destination: String,
        mailbox: String?,
        account: String?
    ) -> HimalayaInvocation {
        HimalayaInvocation(
            ["attachment", "download", id, "--downloads-dir", destination] + folderArgs(
                mailbox,
                account: account
            ) +
                accountArgs(account)
        )
    }

    public func deleteMessages(ids: [String], mailbox: String?, account: String?) -> HimalayaInvocation {
        HimalayaInvocation(["message", "delete"] + ids + folderArgs(mailbox, account: account) +
            accountArgs(account))
    }

    public func listAccountsJSON() -> HimalayaInvocation {
        HimalayaInvocation(["account", "list", "-o", "json"])
    }

    public func probeAccount(_ name: String) -> HimalayaInvocation {
        HimalayaInvocation(["folder", "list", "--account", name])
    }
}
