import AppConfiguration
import CascadeKit
import Foundation
import Synchronization
import Testing
@testable import App

/// A stub executable service so requests can be tested without shelling out to `himalaya`.
private struct StubExecutable: ExecutableService {
    let output: String
    func run(executable: String, arguments: [String]) throws -> String {
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

    func run(executable: String, arguments: [String]) throws -> String {
        calls.withLock { $0.append((executable, arguments)) }
        return output
    }
}

/// A himalaya stub that records the arguments of the last `run` call.
private final class RecordingHimalaya: HimalayaService {
    let calls = Mutex<[[String]]>([])
    let output: String
    init(output: String = "") {
        self.output = output
    }

    func resolveExecutablePath() throws -> String {
        "/usr/local/bin/himalaya"
    }

    func run(arguments: [String]) throws -> String {
        calls.withLock { $0.append(arguments) }
        return output
    }
}

/// Builds a container wired with a recording himalaya service, and returns both.
private func appWithRecordingHimalaya(output: String = "") -> (Application, RecordingHimalaya) {
    let app = Application()
    let himalaya = RecordingHimalaya(output: output)
    app.register(HimalayaServiceKey.self) { _ in himalaya }
    return (app, himalaya)
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
        "message", "write", "--header", "To:a@b.c", "--header", "Subject:Hi", "Hello"
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
        "message", "reply", "5", "--all", "--folder", "INBOX", "Thanks"
    ]])
}

@Test
func draftReplyOmitsAllFlagWhenNotRequested() async throws {
    let (app, himalaya) = appWithRecordingHimalaya()
    _ = try await DraftReplyRequest().execute(DraftReplyRequest.Input(id: "5"), in: app)

    #expect(himalaya.calls.withLock { $0 } == [["message", "reply", "5"]])
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
    #expect(himalaya.calls.withLock { $0 } == [[
        "message", "send", "--account", "work", "raw message"
    ]])
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
func defaultAccountInjectedWhenAbsent() {
    let args = HimalayaServiceDefault.applyingDefaults(
        to: ["envelope", "list"], account: "work", folder: nil
    )
    #expect(args == ["envelope", "list", "--account", "work"])
}

@Test
func defaultAccountNotInjectedWhenExplicit() {
    let args = HimalayaServiceDefault.applyingDefaults(
        to: ["envelope", "list", "--account", "perso"], account: "work", folder: nil
    )
    #expect(args == ["envelope", "list", "--account", "perso"])
}

@Test
func defaultFolderInjectedForFolderAcceptingCommand() {
    let args = HimalayaServiceDefault.applyingDefaults(
        to: ["message", "read", "5"], account: nil, folder: "Archive"
    )
    #expect(args == ["message", "read", "5", "--folder", "Archive"])
}

@Test
func defaultFolderNotInjectedForFolderSubcommands() {
    // `folder list`, `message write` and `message send` don't accept --folder.
    #expect(HimalayaServiceDefault.commandAcceptsFolder(["folder", "list"]) == false)
    #expect(HimalayaServiceDefault.commandAcceptsFolder(["message", "write"]) == false)
    #expect(HimalayaServiceDefault.commandAcceptsFolder(["message", "send"]) == false)
    #expect(HimalayaServiceDefault.commandAcceptsFolder(["message", "read", "1"]) == true)
    #expect(HimalayaServiceDefault.commandAcceptsFolder(["envelope", "list"]) == true)

    let args = HimalayaServiceDefault.applyingDefaults(
        to: ["folder", "list"], account: nil, folder: "Archive"
    )
    #expect(args == ["folder", "list"]) // no --folder added
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
