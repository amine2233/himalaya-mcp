import Foundation

/// Live `ExecutableService`: runs a real subprocess via Foundation `Process`.
///
/// Enforces a wall-clock timeout: if the process runs longer than
/// `timeoutMilliseconds`, it is terminated and `AppError.commandTimedOut` is
/// thrown. A timeout of `0` disables the limit.
public struct ExecutableServiceDefault: ExecutableService {
    /// Command timeout in milliseconds. `0` means no timeout.
    public let timeoutMilliseconds: Int

    public init(timeoutMilliseconds: Int = 120_000) {
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public func run(executable: String, arguments: [String], standardInput: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()

        let inputHandle = inputPipe.fileHandleForWriting
        if let standardInput { inputHandle.write(Data(standardInput.utf8)) }
        try? inputHandle.close()

        var timedOut = false
        if timeoutMilliseconds > 0 {
            if exited.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .timedOut {
                timedOut = true
                process.terminate()
                exited.wait()
            }
        } else {
            exited.wait()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if timedOut {
            throw AppError.commandTimedOut(milliseconds: timeoutMilliseconds)
        }

        let stdout = String(decoding: stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: stderrData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            let detail = stderr.isEmpty ? stdout : stderr
            throw AppError.commandFailed(exitCode: process.terminationStatus, output: detail)
        }

        return stdout
    }
}
