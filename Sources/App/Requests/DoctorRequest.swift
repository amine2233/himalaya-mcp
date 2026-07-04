import CascadeKit
import Foundation

/// Health of a single himalaya account.
public struct AccountHealth: Sendable, Codable, Equatable {
    public let name: String
    public let isDefault: Bool
    public let backend: String?
    /// Whether the account is reachable (a folder listing succeeded).
    public let ok: Bool
    /// `"reachable"` or the error surfaced while probing.
    public let detail: String
}

/// Overall diagnosis produced by `DoctorRequest`.
public struct DoctorReport: Sendable, Codable, Equatable {
    /// Resolved himalaya binary path, or `nil` if it couldn't be found.
    public let himalayaPath: String?
    public let accounts: [AccountHealth]
    /// True when himalaya was found and every checked account is reachable.
    public let ok: Bool
}

/// Diagnoses himalaya: locates the binary, discovers accounts, and probes each
/// for reachability by listing its folders. Read-only.
public struct DoctorRequest: Request {
    public struct Input: Sendable, Decodable {
        /// Limit the check to one account. `nil` checks every configured account.
        public let account: String?

        public init(account: String? = nil) {
            self.account = account
        }
    }

    public init() {}

    public func execute(_ input: Input, in application: Application) async throws -> DoctorReport {
        let himalaya = application.make(HimalayaServiceKey.self)

        guard let path = try? himalaya.resolveExecutablePath() else {
            return DoctorReport(himalayaPath: nil, accounts: [], ok: false)
        }

        let discovered = Self
            .parseAccounts((try? himalaya.run(arguments: ["account", "list", "-o", "json"])) ?? "")
        let targets: [(name: String, isDefault: Bool, backend: String?)] = if let requested = input.account {
            [discovered.first { $0.name == requested } ?? (name: requested, isDefault: false, backend: nil)]
        } else {
            discovered
        }

        let accounts = targets.map { target -> AccountHealth in
            let output = (try? himalaya.run(arguments: ["folder", "list", "--account", target.name])) ?? ""
            let reachable = output.contains("NAME")
            return AccountHealth(
                name: target.name,
                isDefault: target.isDefault,
                backend: target.backend,
                ok: reachable,
                detail: reachable ? "reachable" : Self.meaningfulError(output)
            )
        }

        let ok = !accounts.isEmpty && accounts.allSatisfy(\.ok)
        return DoctorReport(himalayaPath: path, accounts: accounts, ok: ok)
    }

    /// Extracts the account objects from `himalaya account list -o json` output,
    /// tolerating leading log/warning lines by scanning for the JSON array line.
    static func parseAccounts(_ output: String) -> [(name: String, isDefault: Bool, backend: String?)] {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["),
                  let data = trimmed.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                continue
            }

            return array.map { object in
                (
                    name: object["name"] as? String ?? "",
                    isDefault: object["default"] as? Bool ?? false,
                    backend: object["backend"] as? String
                )
            }
        }
        return []
    }

    /// The most meaningful line of a failed probe's output (skips log noise).
    static func meaningfulError(_ output: String) -> String {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("WARN") && !$0.contains("INFO") }
        return lines.last ?? "unreachable"
    }
}
