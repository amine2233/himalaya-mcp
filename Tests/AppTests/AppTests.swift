import Testing
import Foundation
import Synchronization
import CascadeKit
import AppConfiguration
@testable import App

/// A stub executable service so requests can be tested without shelling out to `himalaya`.
private struct StubExecutable: ExecutableService {
    let output: String
    func run(executable: String, arguments: [String]) throws -> String { output }
}

/// An executable stub that records the last `(executable, arguments)` it was asked to run.
private final class RecordingExecutable: ExecutableService {
    let calls = Mutex<[(executable: String, arguments: [String])]>([])
    let output: String
    init(output: String) { self.output = output }
    func run(executable: String, arguments: [String]) throws -> String {
        calls.withLock { $0.append((executable, arguments)) }
        return output
    }
}

@Test func executableServiceResolvesFromContainer() throws {
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

@Test func himalayaOverridePathTakesPriority() throws {
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

@Test func himalayaOverrideMustBeExecutable() throws {
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

@Test func himalayaFallsBackToPathSearchInOrder() throws {
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

@Test func himalayaNotFoundThrowsWithSearchedPaths() throws {
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

@Test func himalayaRunForwardsResolvedPathAndArguments() throws {
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

@Test func himalayaServiceRegistrationResolves() async {
    let app = Application()
    await configure(app)

    let service = app.make(HimalayaServiceKey.self)
    #expect(service is HimalayaServiceDefault)
}

@Test func featureFlagsRegistrationResolves() {
    let app = Application()
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in
        FeatureFlags(experimentalEnabled: true)
    }

    #expect(app.make(FeatureFlagsServiceKey.self).experimentalEnabled == true)
}

@Test func singletonIsCachedAndTransientIsRebuilt() {
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

    #expect(singletonBuilds.withLock { $0 } == 1)   // built once, then cached
    #expect(transientBuilds.withLock { $0 } == 2)   // rebuilt each time
}
