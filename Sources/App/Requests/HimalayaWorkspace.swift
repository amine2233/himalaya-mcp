import Foundation

/// Scratch space for requests that drive himalaya's file-emitting commands
/// (`message export`, `attachment download`) and read the results back.
enum HimalayaWorkspace {
    /// Runs `body` with a fresh, isolated temporary directory that is always
    /// removed afterwards, even on throw.
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("himalaya-mcp-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        return try body(directory)
    }

    /// The files himalaya wrote into `directory`, sorted by name.
    static func files(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
