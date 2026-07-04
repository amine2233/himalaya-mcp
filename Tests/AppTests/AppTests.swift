import AppConfiguration
import CascadeKit
import Foundation
import Synchronization
import Testing
@testable import App

/// A stub executable service so requests can be tested without shelling out to `himalaya`.
private struct StubExecutable: ExecutableService {
    let output: String
    func run(executable: String, arguments: [String], standardInput: String?) throws -> String {
        output
    }
}

/// An executable stub that records the last `(executable, arguments)` it was asked to run.
private final class RecordingExecutable: ExecutableService {
    let calls = Mutex<[(executable: String, arguments: [String])]>([])
    let output: String
    init(output: String) {
        self.output = output
    }

    func run(executable: String, arguments: [String], standardInput: String?) throws -> String {
        calls.withLock { $0.append((executable, arguments)) }
        return output
    }
}

/// A himalaya stub that records the arguments and stdin of each `run` call.
private final class RecordingHimalaya: HimalayaService {
    let calls = Mutex<[[String]]>([])
    let stdins = Mutex<[String?]>([])
    let output: String
    init(output: String = "") {
        self.output = output
    }

    func resolveExecutablePath() throws -> String {
        "/usr/local/bin/himalaya"
    }

    func run(arguments: [String], standardInput: String?) throws -> String {
        calls.withLock { $0.append(arguments) }
        stdins.withLock { $0.append(standardInput) }
        return output
    }
}

/// Builds a container wired with a recording himalaya service (and a v1 dialect),
/// and returns both.
private func appWithRecordingHimalaya(
    output: String = "",
    dialect: any HimalayaDialect = HimalayaDialectV1()
) -> (Application, RecordingHimalaya) {
    let app = Application()
    let himalaya = RecordingHimalaya(output: output)
    app.register(HimalayaServiceKey.self) { _ in himalaya }
    app.register(HimalayaDialectKey.self) { _ in dialect }
    return (app, himalaya)
}

/// A himalaya stub whose output depends on the arguments (for multi-call flows).
/// `resolvable` controls whether `resolveExecutablePath()` succeeds.
private struct ScriptedHimalaya: HimalayaService {
    var resolvable = true
    let handler: @Sendable ([String]) -> String

    func resolveExecutablePath() throws -> String {
        guard resolvable else { throw AppError.himalayaExecutableNotFound(searchedPaths: []) }

        return "/usr/local/bin/himalaya"
    }

    func run(arguments: [String], standardInput: String?) throws -> String {
        handler(arguments)
    }
}

private func appWithScriptedHimalaya(_ himalaya: ScriptedHimalaya) -> Application {
    let app = Application()
    app.register(HimalayaServiceKey.self) { _ in himalaya }
    app.register(HimalayaDialectKey.self) { _ in HimalayaDialectV1() }
    return app
}

@Test
func listEmailsBuildsArgumentsWithAllOptions() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "envelopes")
    let input = ListEmailsRequest.Input(folder: "Archive", pageSize: 20, page: 2, account: "work")

    let output = try await ListEmailsRequest().execute(input, in: app)

    #expect(output == "envelopes")
    #expect(himalaya.calls.withLock { $0 } == [[
        "envelope", "list", "--folder", "Archive", "--page-size", "20", "--page", "2", "--account", "work"
    ]])
}

@Test
func listEmailsOmitsUnsetOptions() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()

    _ = try await ListEmailsRequest().execute(ListEmailsRequest.Input(), in: app)

    #expect(himalaya.calls.withLock { $0 } == [["envelope", "list"]])
}

@Test
func listEmailsInputDecodesSnakeCasePageSize() throws {
    let data = Data(#"{"page_size":50,"page":3}"#.utf8)
    let input = try JSONDecoder().decode(ListEmailsRequest.Input.self, from: data)

    #expect(input.pageSize == 50)
    #expect(input.page == 3)
}

@Test
func searchEmailsSplitsQueryIntoTokens() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = SearchEmailsRequest.Input(query: "from alice and subject invoice", folder: "INBOX")

    _ = try await SearchEmailsRequest().execute(input, in: app)

    #expect(himalaya.calls.withLock { $0 } == [[
        "envelope", "list", "--folder", "INBOX", "from", "alice", "and", "subject", "invoice"
    ]])
}

@Test
func readEmailUsesNoHeaders() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "body")
    let input = ReadEmailRequest.Input(id: "42", account: "work")

    let output = try await ReadEmailRequest().execute(input, in: app)

    #expect(output == "body")
    #expect(himalaya.calls.withLock { $0 } == [[
        "message", "read", "42", "--no-headers", "--account", "work"
    ]])
}

@Test
func readEmailHtmlExportsAndReturnsHtmlPart() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()

    let output = try await ReadEmailHtmlRequest().execute(
        ReadEmailHtmlRequest.Input(id: "7", folder: "INBOX"),
        in: app
    )

    // The stub writes no files, so no HTML part is found — but the export command
    // must have been issued with a --destination temp directory.
    #expect(output == "No HTML part found for message 7.")
    let call = try #require(himalaya.calls.withLock { $0 }.first)
    #expect(call.prefix(3) == ["message", "export", "7"])
    #expect(call.contains("--destination"))
    #expect(call.contains("--folder"))
    #expect(call.contains("INBOX"))
}

@Test
func listFoldersBuildsArguments() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "folders")
    let output = try await ListFoldersRequest().execute(ListFoldersRequest.Input(account: "work"), in: app)

    #expect(output == "folders")
    #expect(himalaya.calls.withLock { $0 } == [["folder", "list", "--account", "work"]])
}

@Test
func createFolderBuildsArguments() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await CreateFolderRequest().execute(CreateFolderRequest.Input(name: "Archive"), in: app)

    #expect(himalaya.calls.withLock { $0 } == [["folder", "add", "Archive"]])
}

@Test
func deleteFolderBuildsArguments() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await DeleteFolderRequest().execute(
        DeleteFolderRequest.Input(name: "Old", account: "work"),
        in: app
    )

    #expect(himalaya.calls.withLock { $0 } == [["folder", "delete", "Old", "--account", "work"]])
}

@Test
func flagEmailAddsFlags() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = FlagEmailRequest.Input(id: "9", flags: "Seen Flagged", action: .add, folder: "INBOX")
    _ = try await FlagEmailRequest().execute(input, in: app)

    #expect(himalaya.calls.withLock { $0 } == [[
        "flag", "add", "9", "Seen", "Flagged", "--folder", "INBOX"
    ]])
}

@Test
func flagEmailRemovesFlags() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await FlagEmailRequest().execute(
        FlagEmailRequest.Input(id: "9", flags: "Seen", action: .remove),
        in: app
    )

    #expect(himalaya.calls.withLock { $0 } == [["flag", "remove", "9", "Seen"]])
}

@Test
func flagEmailRejectsEmptyFlags() async throws {
    let (app, _) = appWithRecordingHimalaya()
    await #expect(throws: AppError.invalidArgument("flag_email requires at least one flag.")) {
        try await FlagEmailRequest().execute(
            FlagEmailRequest.Input(id: "9", flags: "   ", action: .add),
            in: app
        )
    }
}

@Test
func moveEmailPutsTargetBeforeId() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = MoveEmailRequest.Input(id: "3", targetFolder: "Archive", folder: "INBOX", account: "work")
    _ = try await MoveEmailRequest().execute(input, in: app)

    #expect(himalaya.calls.withLock { $0 } == [[
        "message", "move", "Archive", "3", "--folder", "INBOX", "--account", "work"
    ]])
}

@Test
func moveEmailInputDecodesTargetFolderSnakeCase() throws {
    let data = Data(#"{"id":"3","target_folder":"Archive"}"#.utf8)
    let input = try JSONDecoder().decode(MoveEmailRequest.Input.self, from: data)

    #expect(input.targetFolder == "Archive")
}

@Test
func composeEmailBuildsHeadersAndBody() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "template")
    let input = ComposeEmailRequest.Input(to: "a@b.c", subject: "Hi", body: "Hello")
    let output = try await ComposeEmailRequest().execute(input, in: app)

    #expect(output == "template")
    #expect(himalaya.calls.withLock { $0 } == [[
        "template", "write", "--header", "To:a@b.c", "--header", "Subject:Hi", "Hello"
    ]])
}

@Test
func composeEmailAppendsAttachmentMML() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = ComposeEmailRequest.Input(
        to: "a@b.c",
        subject: "Hi",
        body: "Hello",
        attachments: ["/tmp/report.pdf"]
    )
    _ = try await ComposeEmailRequest().execute(input, in: app)

    let body = try #require(himalaya.calls.withLock { $0 }.first?.last)
    #expect(body.contains("Hello"))
    #expect(body.contains(#"<#part filename="/tmp/report.pdf" disposition=attachment><#/part>"#))
}

@Test
func draftReplyUsesAllFlag() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = DraftReplyRequest.Input(id: "5", body: "Thanks", replyAll: true, folder: "INBOX")
    _ = try await DraftReplyRequest().execute(input, in: app)

    #expect(himalaya.calls.withLock { $0 } == [[
        "template", "reply", "5", "--all", "--folder", "INBOX", "Thanks"
    ]])
}

@Test
func draftReplyOmitsAllFlagWhenNotRequested() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await DraftReplyRequest().execute(DraftReplyRequest.Input(id: "5"), in: app)

    #expect(himalaya.calls.withLock { $0 } == [["template", "reply", "5"]])
}

@Test
func sendEmailRefusesWithoutConfirmation() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let output = try await SendEmailRequest().execute(SendEmailRequest.Input(template: "raw"), in: app)

    #expect(output == "Refusing to send: set confirm=true to actually send the message.")
    // himalaya must not have been invoked.
    #expect(himalaya.calls.withLock { $0 }.isEmpty)
}

@Test
func sendEmailSendsWhenConfirmed() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "")
    let input = SendEmailRequest.Input(template: "raw message", confirm: true, account: "work")
    let output = try await SendEmailRequest().execute(input, in: app)

    #expect(output == "Message sent.")
    #expect(himalaya.calls.withLock { $0 } == [["template", "send", "--account", "work"]])
    #expect(himalaya.stdins.withLock { $0 } == ["raw message"])
}

@Test
func sendTemplateSendsInlineTemplateWhenConfirmed() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let input = SendTemplateRequest.Input(template: "From: a@b.c\n\nHi", confirm: true)
    let output = try await SendTemplateRequest().execute(input, in: app)

    #expect(output == "Template sent.")
    #expect(himalaya.calls.withLock { $0 } == [["template", "send"]])
    #expect(himalaya.stdins.withLock { $0 } == ["From: a@b.c\n\nHi"])
}

@Test
func sendTemplateRefusesWithoutConfirmation() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    let output = try await SendTemplateRequest().execute(
        SendTemplateRequest.Input(template: "x", confirm: false), in: app
    )
    #expect(output == "Refusing to send: set confirm=true to actually send the template.")
    #expect(himalaya.calls.withLock { $0 }.isEmpty)
}

@Test
func sendTemplateReadsFromFile() async throws {
    let fileManager = FileManager.default
    let dir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: dir) }
    let file = dir.appendingPathComponent("draft.eml")
    try Data("From: a@b.c\n\nFrom a file".utf8).write(to: file)

    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await SendTemplateRequest().execute(
        SendTemplateRequest.Input(templateFile: file.path, confirm: true), in: app
    )
    #expect(himalaya.calls.withLock { $0 } == [["template", "send"]])
    #expect(himalaya.stdins.withLock { $0 } == ["From: a@b.c\n\nFrom a file"])
}

@Test
func sendTemplateRejectsAmbiguousOrMissingSource() async throws {
    let (app, _) = appWithRecordingHimalaya()
    await #expect(throws: AppError.invalidArgument("Provide a \"template\" or \"template_file\" to send.")) {
        try await SendTemplateRequest().execute(SendTemplateRequest.Input(confirm: true), in: app)
    }
    await #expect(throws: AppError
        .invalidArgument("Provide only one of \"template\" or \"template_file\".")) {
        try await SendTemplateRequest().execute(
            SendTemplateRequest.Input(template: "x", templateFile: "/y", confirm: true), in: app
        )
    }
}

@Test
func deleteEmailBuildsArgumentsWithMultipleIds() async throws {
    let (app, himalaya) = appWithRecordingHimalaya(output: "")
    let input = DeleteEmailRequest.Input(ids: ["3", "4"], folder: "INBOX", account: "work")
    let output = try await DeleteEmailRequest().execute(input, in: app)

    #expect(output == "Deleted 2 message(s): 3, 4.")
    #expect(himalaya.calls.withLock { $0 } == [[
        "message", "delete", "3", "4", "--folder", "INBOX", "--account", "work"
    ]])
}

@Test
func deleteEmailRejectsEmptyIds() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    await #expect(throws: AppError.invalidArgument("delete_email requires at least one id.")) {
        try await DeleteEmailRequest().execute(DeleteEmailRequest.Input(ids: [""]), in: app)
    }
    #expect(himalaya.calls.withLock { $0 }.isEmpty)
}

@Test
func v1DialectAppliesDefaultAccountAndFolder() {
    let dialect = HimalayaDialectV1(defaultAccount: "work", defaultFolder: "Archive")
    // Defaults fill in when the call omits them.
    #expect(dialect.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: nil).arguments
        == ["envelope", "list", "--folder", "Archive", "--account", "work"])
    // Explicit values win over defaults.
    #expect(dialect.listEnvelopes(mailbox: "INBOX", pageSize: nil, page: nil, account: "perso").arguments
        == ["envelope", "list", "--folder", "INBOX", "--account", "perso"])
    // `account list` / `mailbox list` don't carry --folder.
    #expect(dialect.listAccountsJSON().arguments == ["account", "list", "-o", "json"])
}

@Test
func doctorReportsReachableAccounts() async throws {
    let app = appWithScriptedHimalaya(ScriptedHimalaya { args in
        if args.first == "account" {
            return "[{\"name\":\"work\",\"backend\":\"IMAP, SMTP\",\"default\":true}]"
        }
        return "| NAME | DESC |\n| INBOX | ... |" // folder list success
    })

    let report = try await DoctorRequest().execute(.init(), in: app)

    #expect(report.ok)
    #expect(report.himalayaPath == "/usr/local/bin/himalaya")
    #expect(report.accounts.count == 1)
    #expect(report.accounts.first?.name == "work")
    #expect(report.accounts.first?.isDefault == true)
    #expect(report.accounts.first?.ok == true)
    #expect(report.accounts.first?.detail == "reachable")
}

@Test
func doctorReportsUnreachableAccount() async throws {
    let app = appWithScriptedHimalaya(ScriptedHimalaya { args in
        if args.first == "account" {
            return "[{\"name\":\"work\",\"backend\":\"IMAP\",\"default\":true}]"
        }
        return "Error: cannot connect to IMAP server" // folder list failure
    })

    let report = try await DoctorRequest().execute(.init(), in: app)

    #expect(report.ok == false)
    #expect(report.accounts.first?.ok == false)
    #expect(report.accounts.first?.detail == "Error: cannot connect to IMAP server")
}

@Test
func doctorChecksSingleAccount() async throws {
    let probed = Mutex<[[String]]>([])
    let app = appWithScriptedHimalaya(ScriptedHimalaya { args in
        probed.withLock { $0.append(args) }
        if args
            .first ==
            "account" {
            return "[{\"name\":\"work\",\"default\":true},{\"name\":\"perso\",\"default\":false}]"
        }
        return "| NAME |"
    })

    let report = try await DoctorRequest().execute(.init(account: "perso"), in: app)

    #expect(report.accounts.count == 1)
    #expect(report.accounts.first?.name == "perso")
    // The folder-list probe targeted exactly the requested account.
    #expect(probed.withLock { $0 }.contains(["folder", "list", "--account", "perso"]))
}

@Test
func doctorReportsMissingHimalaya() async throws {
    let app = appWithScriptedHimalaya(ScriptedHimalaya(resolvable: false) { _ in "" })

    let report = try await DoctorRequest().execute(.init(), in: app)

    #expect(report.himalayaPath == nil)
    #expect(report.ok == false)
    #expect(report.accounts.isEmpty)
}

@Test
func v2DialectMapsCommandsAndRejectsUnsupported() {
    let v2 = HimalayaDialectV2()
    // Renamed / reshaped commands.
    #expect(v2.listEnvelopes(mailbox: "INBOX", pageSize: 10, page: 1, account: "work").arguments
        == [
            "envelope",
            "list",
            "--mailbox",
            "INBOX",
            "--page-size",
            "10",
            "--page",
            "1",
            "--account",
            "work"
        ])
    #expect(try v2.searchEnvelopes(query: "from a", mailbox: nil, account: nil).arguments
        == ["envelope", "search", "from", "a"])
    #expect(v2.listMailboxes(account: nil).arguments == ["mailbox", "list"])
    #expect(v2.setFlags(id: "5", flags: ["Seen", "Flagged"], add: true, mailbox: nil, account: nil).arguments
        == ["flag", "add", "--flag", "Seen", "--flag", "Flagged", "5"])
    #expect(v2.moveMessage(id: "5", target: "Archive", mailbox: "INBOX", account: nil).arguments
        == ["message", "move", "--to", "Archive", "--from", "INBOX", "5"])
    #expect(v2.listAccountsJSON().arguments == ["account", "list", "--json"])
    #expect(v2.sendTemplate("raw", account: nil) == HimalayaInvocation(
        ["message", "send"],
        standardInput: "raw"
    ))

    // Commands that v2 doesn't offer surface a clear error.
    #expect(throws: AppError
        .invalidArgument("Deleting messages (delete_email) is not supported on himalaya v2.")) {
        try v2.deleteMessages(ids: ["1"], mailbox: nil, account: nil)
    }
    #expect(throws: (any Error).self) { try v2.exportMessage(
        id: "1",
        destination: "/tmp",
        mailbox: nil,
        account: nil
    ) }
    #expect(throws: (any Error).self) { try v2.createMailbox(name: "X", account: nil) }
}

// MARK: - Full v1 dialect argument generation

@Test
func v1DialectGeneratesEveryCommand() throws {
    let d = HimalayaDialectV1()

    #expect(d.listEnvelopes(mailbox: "INBOX", pageSize: 20, page: 2, account: "work").arguments
        == ["envelope", "list", "--folder", "INBOX", "--page-size", "20", "--page", "2", "--account", "work"])
    #expect(d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: nil).arguments
        == ["envelope", "list"])
    #expect(try d.searchEnvelopes(query: "from a and subject b", mailbox: "INBOX", account: nil).arguments
        == ["envelope", "list", "--folder", "INBOX", "from", "a", "and", "subject", "b"])
    #expect(try d.readMessage(id: "42", mailbox: nil, account: "work").arguments
        == ["message", "read", "42", "--no-headers", "--account", "work"])
    #expect(try d.exportMessage(id: "7", destination: "/tmp/x", mailbox: "INBOX", account: nil).arguments
        == ["message", "export", "7", "--destination", "/tmp/x", "--folder", "INBOX"])
    #expect(try d.listMailboxes(account: "work").arguments == ["folder", "list", "--account", "work"])
    #expect(try d.createMailbox(name: "Archive", account: nil).arguments == ["folder", "add", "Archive"])
    #expect(try d.deleteMailbox(name: "Old", account: "work").arguments
        == ["folder", "delete", "Old", "--account", "work"])
    #expect(try d.setFlags(id: "9", flags: ["Seen", "Flagged"], add: true, mailbox: "INBOX", account: nil)
        .arguments
        == ["flag", "add", "9", "Seen", "Flagged", "--folder", "INBOX"])
    #expect(try d.setFlags(id: "9", flags: ["Seen"], add: false, mailbox: nil, account: nil).arguments
        == ["flag", "remove", "9", "Seen"])
    #expect(try d.moveMessage(id: "3", target: "Archive", mailbox: "INBOX", account: "work").arguments
        == ["message", "move", "Archive", "3", "--folder", "INBOX", "--account", "work"])
    #expect(try d.composeTemplate(to: "a@b.c", subject: "Hi", body: "Body", account: nil).arguments
        == ["template", "write", "--header", "To:a@b.c", "--header", "Subject:Hi", "Body"])
    #expect(try d.replyTemplate(id: "5", body: "Thanks", all: true, mailbox: "INBOX", account: nil).arguments
        == ["template", "reply", "5", "--all", "--folder", "INBOX", "Thanks"])
    #expect(try d.replyTemplate(id: "5", body: nil, all: false, mailbox: nil, account: nil).arguments
        == ["template", "reply", "5"])
    #expect(try d.sendTemplate("RAW", account: "work") == HimalayaInvocation(
        ["template", "send", "--account", "work"],
        standardInput: "RAW"
    ))
    #expect(try d.listAttachments(id: "7", destination: "/tmp/a", mailbox: nil, account: nil).arguments
        == ["attachment", "download", "7", "--downloads-dir", "/tmp/a"])
    #expect(try d.downloadAttachments(id: "7", destination: "/tmp/a", mailbox: "INBOX", account: nil)
        .arguments
        == ["attachment", "download", "7", "--downloads-dir", "/tmp/a", "--folder", "INBOX"])
    #expect(try d.deleteMessages(ids: ["3", "4"], mailbox: "INBOX", account: "work").arguments
        == ["message", "delete", "3", "4", "--folder", "INBOX", "--account", "work"])
    #expect(d.listAccountsJSON().arguments == ["account", "list", "-o", "json"])
    #expect(d.probeAccount("work").arguments == ["folder", "list", "--account", "work"])
}

@Test
func v1DialectDefaultsFillOnlyWhenOmitted() throws {
    let d = HimalayaDialectV1(defaultAccount: "work", defaultFolder: "Archive")
    #expect(try d.readMessage(id: "1", mailbox: nil, account: nil).arguments
        == ["message", "read", "1", "--no-headers", "--folder", "Archive", "--account", "work"])
    #expect(try d.readMessage(id: "1", mailbox: "Sent", account: "perso").arguments
        == ["message", "read", "1", "--no-headers", "--folder", "Sent", "--account", "perso"])
}

@Test
func v1DialectUsesPerAccountInboxWhenFolderOmitted() throws {
    let d = HimalayaDialectV1(
        defaultFolder: "INBOX",
        accountFolders: AccountFolderNames { $0 == "outlook" ? "Inbox" : nil }
    )
    // outlook has an override → used as the default folder.
    #expect(try d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: "outlook").arguments
        == ["envelope", "list", "--folder", "Inbox", "--account", "outlook"])
    // proton has no override → falls back to the global default folder.
    #expect(try d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: "proton").arguments
        == ["envelope", "list", "--folder", "INBOX", "--account", "proton"])
    // An explicit folder always wins over the per-account inbox.
    #expect(try d.listEnvelopes(mailbox: "Sent", pageSize: nil, page: nil, account: "outlook").arguments
        == ["envelope", "list", "--folder", "Sent", "--account", "outlook"])
}

@Test
func v1DialectUsesPerAccountInboxForTheDefaultAccount() throws {
    // When no per-call account is given, the default account's override applies.
    let d = HimalayaDialectV1(
        defaultAccount: "outlook",
        accountFolders: AccountFolderNames { $0 == "outlook" ? "Inbox" : nil }
    )
    #expect(try d.readMessage(id: "5", mailbox: nil, account: nil).arguments
        == ["message", "read", "5", "--no-headers", "--folder", "Inbox", "--account", "outlook"])
}

@Test
func v2DialectUsesPerAccountInbox() {
    let d = HimalayaDialectV2(
        defaultFolder: "INBOX",
        accountFolders: AccountFolderNames { $0 == "outlook" ? "Inbox" : nil }
    )
    #expect(d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: "outlook").arguments
        == ["envelope", "list", "--mailbox", "Inbox", "--account", "outlook"])
    #expect(d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: "proton").arguments
        == ["envelope", "list", "--mailbox", "INBOX", "--account", "proton"])
    // move source (--from) is also per-account-aware.
    #expect(d.moveMessage(id: "3", target: "Archive", mailbox: nil, account: "outlook").arguments
        == ["message", "move", "--to", "Archive", "--from", "Inbox", "3", "--account", "outlook"])
}

// MARK: - Full v2 dialect argument generation

@Test
func v2DialectGeneratesSupportedCommands() throws {
    let d = HimalayaDialectV2()

    #expect(d.listEnvelopes(mailbox: "INBOX", pageSize: 20, page: 2, account: "work").arguments
        == [
            "envelope",
            "list",
            "--mailbox",
            "INBOX",
            "--page-size",
            "20",
            "--page",
            "2",
            "--account",
            "work"
        ])
    #expect(try d.searchEnvelopes(query: "from a", mailbox: "INBOX", account: nil).arguments
        == ["envelope", "search", "--mailbox", "INBOX", "from", "a"])
    #expect(try d.readMessage(id: "42", mailbox: "INBOX", account: nil).arguments
        == ["message", "read", "42", "--mailbox", "INBOX"])
    #expect(try d.listMailboxes(account: "work").arguments == ["mailbox", "list", "--account", "work"])
    #expect(try d.setFlags(id: "9", flags: ["Seen", "Flagged"], add: true, mailbox: "INBOX", account: nil)
        .arguments
        == ["flag", "add", "--flag", "Seen", "--flag", "Flagged", "9", "--mailbox", "INBOX"])
    #expect(try d.setFlags(id: "9", flags: ["Seen"], add: false, mailbox: nil, account: nil).arguments
        == ["flag", "remove", "--flag", "Seen", "9"])
    #expect(try d.moveMessage(id: "3", target: "Archive", mailbox: "INBOX", account: "work").arguments
        == ["message", "move", "--to", "Archive", "--from", "INBOX", "3", "--account", "work"])
    #expect(try d.sendTemplate("RAW", account: "work") == HimalayaInvocation(
        ["message", "send", "--account", "work"],
        standardInput: "RAW"
    ))
    #expect(try d.listAttachments(id: "7", destination: "/tmp/a", mailbox: "INBOX", account: nil).arguments
        == ["attachment", "download", "7", "--dir", "/tmp/a", "--mailbox", "INBOX"])
    #expect(try d.downloadAttachments(id: "7", destination: "/tmp/a", mailbox: nil, account: nil).arguments
        == ["attachment", "download", "7", "--dir", "/tmp/a"])
    #expect(d.listAccountsJSON().arguments == ["account", "list", "--json"])
    #expect(d.probeAccount("work").arguments == ["mailbox", "list", "--account", "work"])
}

@Test
func v2DialectDefaultsUseMailboxFlag() {
    let d = HimalayaDialectV2(defaultAccount: "work", defaultFolder: "Archive")
    #expect(d.listEnvelopes(mailbox: nil, pageSize: nil, page: nil, account: nil).arguments
        == ["envelope", "list", "--mailbox", "Archive", "--account", "work"])
}

@Test
func v2DialectRejectsUnsupportedCommands() {
    let d = HimalayaDialectV2()
    for probe: () throws -> Any in [
        { try d.exportMessage(id: "1", destination: "/tmp", mailbox: nil, account: nil) },
        { try d.createMailbox(name: "X", account: nil) },
        { try d.deleteMailbox(name: "X", account: nil) },
        { try d.composeTemplate(to: "a", subject: "b", body: "c", account: nil) },
        { try d.replyTemplate(id: "1", body: nil, all: false, mailbox: nil, account: nil) },
        { try d.deleteMessages(ids: ["1"], mailbox: nil, account: nil) }
    ] {
        #expect(throws: (any Error).self) { _ = try probe() }
    }
}

@Test
func executableServiceTimesOutLongCommand() {
    let service = ExecutableServiceDefault(timeoutMilliseconds: 100)

    #expect(throws: AppError.commandTimedOut(milliseconds: 100)) {
        try service.run(executable: "sleep", arguments: ["3"])
    }
}

@Test
func executableServiceRunsFastCommandWithinTimeout() throws {
    let service = ExecutableServiceDefault(timeoutMilliseconds: 10_000)
    let output = try service.run(executable: "echo", arguments: ["hello"])
    #expect(output == "hello")
}

@Test
func claudeDesktopInstallAddsEntryAndPreservesOtherKeys() throws {
    try withTemporaryDirectory { root in
        let configURL = root.appendingPathComponent("claude_desktop_config.json")
        try Data(#"{"mcpServers":{"other":{"command":"x"}},"preferences":{"keep":true}}"#.utf8)
            .write(to: configURL)

        let setup = ClaudeDesktopSetup(configURL: configURL)
        let entry = ClaudeDesktopSetup.ServerEntry(
            command: "/bin/himalaya-mcp", args: ["serve"], env: ["HIMALAYA_FOLDER": "INBOX"]
        )
        let addOutcome = try setup.install(entry)
        #expect(addOutcome == .added)

        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        let servers = root["mcpServers"] as! [String: Any]
        let himalaya = servers["himalaya-mcp"] as! [String: Any]
        #expect(himalaya["command"] as? String == "/bin/himalaya-mcp")
        #expect(himalaya["args"] as? [String] == ["serve"])
        #expect(servers["other"] != nil) // other server kept
        #expect((root["preferences"] as? [String: Any])?["keep"] as? Bool == true) // prefs kept
    }
}

@Test
func claudeDesktopInstallCreatesFileWhenMissing() throws {
    try withTemporaryDirectory { root in
        let configURL = root.appendingPathComponent("nested/claude_desktop_config.json")
        let setup = ClaudeDesktopSetup(configURL: configURL)

        let entry = ClaudeDesktopSetup.ServerEntry(command: "/bin/himalaya-mcp", args: ["serve"], env: [:])
        let addOutcome = try setup.install(entry)
        #expect(addOutcome == .added)
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        // Re-installing updates rather than adds.
        let updateOutcome = try setup.install(entry)
        #expect(updateOutcome == .updated)
    }
}

@Test
func claudeDesktopRemoveDeletesOnlyOurEntry() throws {
    try withTemporaryDirectory { root in
        let configURL = root.appendingPathComponent("claude_desktop_config.json")
        try Data(#"{"mcpServers":{"himalaya-mcp":{"command":"x"},"other":{"command":"y"}}}"#.utf8)
            .write(to: configURL)
        let setup = ClaudeDesktopSetup(configURL: configURL)

        let removeOutcome = try setup.remove()
        #expect(removeOutcome == .removed)
        let servers = try (JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
            as! [String: Any])["mcpServers"] as! [String: Any]
        #expect(servers["himalaya-mcp"] == nil)
        #expect(servers["other"] != nil)

        let secondRemove = try setup.remove()
        #expect(secondRemove == .notPresent) // already gone
    }
}

@Test
func claudeDesktopCheckReportsHealthAndProblems() throws {
    try withTemporaryDirectory { root in
        // Stage a real executable to serve as both command and himalaya binary.
        let bin = try stageHimalaya(in: root.appendingPathComponent("bin"))
        let configURL = root.appendingPathComponent("claude_desktop_config.json")
        let setup = ClaudeDesktopSetup(configURL: configURL)

        // Missing config → not healthy.
        let missingCheck = try setup.check()
        #expect(missingCheck.isHealthy == false)

        // Healthy after installing with runnable command + HIMALAYA_BIN_PATH.
        try setup.install(.init(command: bin, args: ["serve"], env: ["HIMALAYA_BIN_PATH": bin]))
        let healthy = try setup.check()
        #expect(healthy.isHealthy)
        #expect(healthy.entryPresent)
        #expect(healthy.commandRunnable)
        #expect(healthy.himalayaRunnable)

        // Broken command path → problem reported.
        try setup.install(.init(command: "/nope/himalaya-mcp", args: ["serve"], env: [:]))
        let broken = try setup.check()
        #expect(broken.isHealthy == false)
        #expect(broken.commandRunnable == false)
    }
}

@Test
func executableServiceResolvesFromContainer() throws {
    let app = Application()
    app.register(ExecutableServiceKey.self) { _ in StubExecutable(output: "himalaya 1.0.0") }

    let output = try app.make(ExecutableServiceKey.self).run(executable: "himalaya", arguments: ["--version"])

    #expect(output == "himalaya 1.0.0")
}

/// Creates a throwaway directory tree, runs `body`, then deletes it. `himalaya`
/// resolution hits the real filesystem, so tests stage actual executable files.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

/// Writes an executable `himalaya` stub into `directory` and returns its path.
@discardableResult
private func stageHimalaya(in directory: URL) throws -> String {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("himalaya")
    try Data("#!/bin/sh\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return file.path
}

@Test
func himalayaOverridePathTakesPriority() throws {
    try withTemporaryDirectory { root in
        let overridePath = try stageHimalaya(in: root.appendingPathComponent("custom"))
        let pathDir = root.appendingPathComponent("bin")
        try stageHimalaya(in: pathDir)

        let service = HimalayaServiceDefault(
            executable: StubExecutable(output: ""),
            environment: [
                "HIMALAYA_BIN_PATH": overridePath,
                "PATH": pathDir.path
            ]
        )

        // Even though a himalaya exists on PATH, the override wins.
        #expect(try service.resolveExecutablePath() == overridePath)
    }
}

@Test
func himalayaOverrideMustBeExecutable() throws {
    try withTemporaryDirectory { root in
        let missing = root.appendingPathComponent("nope/himalaya").path
        let service = HimalayaServiceDefault(
            executable: StubExecutable(output: ""),
            environment: ["HIMALAYA_BIN_PATH": missing]
        )

        #expect(throws: AppError.himalayaExecutableNotFound(searchedPaths: [missing])) {
            try service.resolveExecutablePath()
        }
    }
}

@Test
func himalayaFallsBackToPathSearchInOrder() throws {
    try withTemporaryDirectory { root in
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let expected = try stageHimalaya(in: first)
        try stageHimalaya(in: second)
        let empty = root.appendingPathComponent("empty").path

        let service = HimalayaServiceDefault(
            executable: StubExecutable(output: ""),
            environment: ["PATH": "\(empty):\(first.path):\(second.path)"]
        )

        // The empty dir is skipped; the first matching directory in PATH order wins.
        #expect(try service.resolveExecutablePath() == expected)
    }
}

@Test
func himalayaNotFoundThrowsWithSearchedPaths() throws {
    try withTemporaryDirectory { root in
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        let service = HimalayaServiceDefault(
            executable: StubExecutable(output: ""),
            environment: ["PATH": "\(a.path):\(b.path)"]
        )

        let expected = [a.appendingPathComponent("himalaya").path, b.appendingPathComponent("himalaya").path]
        #expect(throws: AppError.himalayaExecutableNotFound(searchedPaths: expected)) {
            try service.resolveExecutablePath()
        }
    }
}

@Test
func himalayaRunForwardsResolvedPathAndArguments() throws {
    try withTemporaryDirectory { root in
        let binDir = root.appendingPathComponent("bin")
        let expected = try stageHimalaya(in: binDir)
        let executable = RecordingExecutable(output: "ok")
        let service = HimalayaServiceDefault(
            executable: executable,
            environment: ["PATH": binDir.path]
        )

        let output = try service.run(arguments: ["envelope", "list", "--folder", "INBOX"])

        #expect(output == "ok")
        let call = executable.calls.withLock { $0 }
        #expect(call.count == 1)
        #expect(call.first?.executable == expected)
        #expect(call.first?.arguments == ["envelope", "list", "--folder", "INBOX"])
    }
}

@Test
func himalayaServiceRegistrationResolves() async {
    let app = Application()
    await configure(app)

    let service = app.make(HimalayaServiceKey.self)
    #expect(service is HimalayaServiceDefault)
}

@Test
func featureFlagsRegistrationResolves() {
    let app = Application()
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in
        FeatureFlags(experimentalEnabled: true)
    }

    #expect(app.make(FeatureFlagsServiceKey.self).experimentalEnabled == true)
}

@Test
func singletonIsCachedAndTransientIsRebuilt() {
    let singletonBuilds = Mutex(0)
    let transientBuilds = Mutex(0)
    let app = Application()

    app.register(ExecutableServiceKey.self, scope: .singleton) { _ in
        singletonBuilds.withLock { $0 += 1 }
        return ExecutableServiceDefault()
    }
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in
        transientBuilds.withLock { $0 += 1 }
        return FeatureFlags(experimentalEnabled: false)
    }

    _ = app.make(ExecutableServiceKey.self)
    _ = app.make(ExecutableServiceKey.self)
    _ = app.make(FeatureFlagsServiceKey.self)
    _ = app.make(FeatureFlagsServiceKey.self)

    #expect(singletonBuilds.withLock { $0 } == 1) // built once, then cached
    #expect(transientBuilds.withLock { $0 } == 2) // rebuilt each time
}
