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

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Always give the child its own stdin pipe so it never reads the parent's
        // stdin (in `serve` mode that's the JSON-RPC stream). We feed the given
        // input, if any, then close to signal EOF.
        let inputPipe = Pipe()
        process.standardInput = inputPipe

        // Signalled when the process exits (naturally or after termination).
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
                exited.wait() // wait for the terminated process to actually finish
            }
        } else {
            exited.wait()
        }

        // The process has ended, so its write end is closed: this reads to EOF.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if timedOut {
            throw AppError.commandTimedOut(milliseconds: timeoutMilliseconds)
        }

        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            throw AppError.commandFailed(exitCode: process.terminationStatus, output: output)
        }

        return output
    }
}
