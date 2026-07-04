import Foundation

/// Live `ExecutableService`: runs a real subprocess via Foundation `Process`.
public struct ExecutableServiceDefault: ExecutableService {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
