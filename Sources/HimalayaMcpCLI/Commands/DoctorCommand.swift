import App
import ArgumentParser
import Foundation

/// Diagnoses himalaya and its accounts.
///
/// Usage:
///   himalaya-mcp doctor                  # check all accounts
///   himalaya-mcp doctor --account work   # check one account
///   himalaya-mcp doctor --json           # machine-readable output
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that himalaya and its accounts are reachable."
    )

    @Option(name: .long, help: "Check only this account (defaults to all).")
    var account: String?

    @Flag(name: .long, help: "Emit the report as JSON.")
    var json = false

    func run() async throws {
        let report = try await DoctorRequest().execute(.init(account: account), in: app)

        if json {
            try printJSON(report)
        } else {
            printText(report)
        }

        if !report.ok {
            throw ExitCode.failure
        }
    }

    private func printJSON(_ report: DoctorReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(report)
        print(String(decoding: data, as: UTF8.self))
    }

    private func printText(_ report: DoctorReport) {
        if let path = report.himalayaPath {
            print("himalaya: \(mark(true)) \(path)")
        } else {
            print("himalaya: \(mark(false)) not found (set HIMALAYA_BIN_PATH or add it to PATH)")
        }

        if report.accounts.isEmpty {
            print("accounts: none configured")
        } else {
            print("accounts:")
            for account in report.accounts {
                let star = account.isDefault ? " (default)" : ""
                let backend = account.backend.map { " [\($0)]" } ?? ""
                print("  \(mark(account.ok)) \(account.name)\(star)\(backend) — \(account.detail)")
            }
        }

        print(report.ok ? "OK — all checks passed." : "Problems found.")
    }

    private func mark(_ ok: Bool) -> String {
        ok ? "✓" : "✗"
    }
}
