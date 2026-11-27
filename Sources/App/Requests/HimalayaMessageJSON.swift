import Foundation

/// Read-only view over `himalaya message read --json` output (mail-parser's
/// message model): top-level `parts`, each with `headers` and a decoded `body`,
/// plus `html_body`/`text_body` arrays indexing into `parts`. The first part
/// carries the message headers.
struct HimalayaMessageJSON {
    private let root: [String: Any]

    init(_ output: String) throws {
        guard
            let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            throw AppError.invalidArgument("Unexpected himalaya JSON output: \(output.prefix(200))")
        }

        self.root = root
    }

    private var parts: [[String: Any]] {
        root["parts"] as? [[String: Any]] ?? []
    }

    /// Decoded HTML of every part listed in `html_body`, in order. Text parts that
    /// `html_body` falls back to (when the message has no HTML) are skipped.
    var htmlBodies: [String] {
        let indices = root["html_body"] as? [Int] ?? []
        return indices.compactMap { index -> String? in
            guard parts.indices.contains(index), let body = parts[index]["body"] as? [String: Any] else {
                return nil
            }

            return body["Html"] as? String
        }
    }

    /// Addresses of the header named `name` (mail-parser's snake_case name, e.g.
    /// `to`, `cc`, `reply_to`), or of an unrecognised header such as
    /// `X-Original-To` (matched case-insensitively). Lower-cased.
    func addresses(inHeader name: String) -> [String] {
        let headers = parts.first?["headers"] as? [[String: Any]] ?? []
        return headers.filter { Self.headerName($0["name"]).caseInsensitiveCompare(name) == .orderedSame }
            .flatMap { Self.addresses(in: $0["value"]) }
    }

    private static func headerName(_ raw: Any?) -> String {
        if let name = raw as? String { return name }
        if let other = (raw as? [String: Any])?["other"] as? String { return other }
        return ""
    }

    /// Accepts `{"Address": {"List": [...]}}`, `{"Address": {"Group": [...]}}`
    /// and `{"Text": "a@b.c"}` header values.
    private static func addresses(in value: Any?) -> [String] {
        guard let value = value as? [String: Any] else { return [] }

        if let text = value["Text"] as? String {
            return text.contains("@") ? [text.trimmingCharacters(in: .whitespaces).lowercased()] : []
        }
        guard let address = value["Address"] as? [String: Any] else { return [] }

        var entries = address["List"] as? [[String: Any]] ?? []
        for group in address["Group"] as? [[String: Any]] ?? [] {
            entries += group["addresses"] as? [[String: Any]] ?? []
        }
        return entries.compactMap { ($0["address"] as? String)?.lowercased() }
    }
}
