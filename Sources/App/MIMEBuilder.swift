import Foundation

/// Builds a complete RFC 5322 / MIME message from an `EmailComposition`
/// in-process, without the external `mml` binary.
///
/// Used by `send_email` when `mml` is not installed and himalaya v2 can't
/// compile MML itself (`TemplateStrategy.unavailable`). The output is a raw
/// message that `himalaya message send` / `message save` accept verbatim.
///
/// - Text bodies are 7bit when pure ASCII with short lines, base64 otherwise.
/// - Non-ASCII subjects and display names use RFC 2047 encoded-words.
/// - Attachments become base64 parts of a `multipart/mixed` message, with an
///   RFC 2231 `filename*` when the file name isn't ASCII.
/// - CR/LF in header values are replaced by spaces (no header injection).
public struct MIMEBuilder: Sendable {
    private let now: @Sendable () -> Date
    private let makeBoundary: @Sendable () -> String
    private let makeMessageIDLocalPart: @Sendable () -> String
    private let readFile: @Sendable (String) throws -> Data

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        makeBoundary: @escaping @Sendable () -> String = { "=_himalaya-mcp_\(UUID().uuidString)" },
        makeMessageIDLocalPart: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        readFile: @escaping @Sendable (String) throws -> Data = { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    ) {
        self.now = now
        self.makeBoundary = makeBoundary
        self.makeMessageIDLocalPart = makeMessageIDLocalPart
        self.readFile = readFile
    }

    /// Returns the full message with CRLF line endings.
    public func build(_ input: EmailComposition) throws -> String {
        var headers: [String] = []
        if let from = input.from { headers.append("From: \(Self.encodeAddressList(from))") }
        headers.append("To: \(Self.encodeAddressList(input.to))")
        if let cc = input.cc { headers.append("Cc: \(Self.encodeAddressList(cc))") }
        if let bcc = input.bcc { headers.append("Bcc: \(Self.encodeAddressList(bcc))") }
        headers.append("Subject: \(Self.encodeWordIfNeeded(Self.sanitizeHeaderValue(input.subject)))")
        headers.append("Date: \(Self.rfc5322Date(now()))")
        headers.append("Message-ID: <\(makeMessageIDLocalPart())@\(Self.messageIDDomain(from: input.from))>")
        if let addr = input.readReceipt {
            headers.append("Disposition-Notification-To: \(Self.encodeAddressList(addr))")
        }
        headers.append("MIME-Version: 1.0")

        let subtype = input.bodyType == .html ? "html" : "plain"
        let textPart = Self.textPart(input.body, subtype: subtype)

        let crlf = "\r\n"
        guard !input.attachments.isEmpty else {
            return (headers + textPart.headers).joined(separator: crlf) + crlf + crlf + textPart.body
        }

        let boundary = makeBoundary()
        var parts: [String] = [
            textPart.headers.joined(separator: crlf) + crlf + crlf + textPart.body
        ]
        for path in input.attachments {
            let data: Data
            do {
                data = try readFile(path)
            } catch {
                throw AppError.invalidArgument(
                    "Could not read attachment \"\(path)\": \(error.localizedDescription)"
                )
            }
            parts.append(Self.attachmentPart(data: data, path: path))
        }

        headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        var message = headers.joined(separator: crlf) + crlf + crlf
        for part in parts {
            message += "--\(boundary)\(crlf)\(part)\(crlf)"
        }
        message += "--\(boundary)--\(crlf)"
        return message
    }

    // MARK: - Parts

    static func textPart(_ text: String, subtype: String) -> (headers: [String], body: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let isSevenBit = normalized.unicodeScalars.allSatisfy(\.isASCII)
            && lines.allSatisfy { $0.utf8.count <= 998 }

        if isSevenBit {
            return (
                ["Content-Type: text/\(subtype); charset=utf-8", "Content-Transfer-Encoding: 7bit"],
                lines.joined(separator: "\r\n")
            )
        }
        let utf8 = Data(lines.joined(separator: "\r\n").utf8)
        return (
            ["Content-Type: text/\(subtype); charset=utf-8", "Content-Transfer-Encoding: base64"],
            wrappedBase64(utf8)
        )
    }

    static func attachmentPart(data: Data, path: String) -> String {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let mimeType = mimeType(forExtension: URL(fileURLWithPath: path).pathExtension)
        let nameParameter = filenameParameter(filename)
        let headers = [
            "Content-Type: \(mimeType); \(nameParameter.replacingOccurrences(of: "filename", with: "name"))",
            "Content-Disposition: attachment; \(nameParameter)",
            "Content-Transfer-Encoding: base64"
        ]
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + wrappedBase64(data)
    }

    /// `filename="x.pdf"` for plain ASCII names, `filename*=utf-8''…` (RFC 2231) otherwise.
    static func filenameParameter(_ filename: String) -> String {
        let safe = sanitizeHeaderValue(filename)
        if safe.unicodeScalars.allSatisfy({ $0.isASCII }) {
            let escaped = safe
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "filename=\"\(escaped)\""
        }
        // RFC 2231 attribute-char: ASCII letters, digits and a few safe symbols.
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&+-.^_`|~"
        )
        let encoded = safe.addingPercentEncoding(withAllowedCharacters: allowed) ?? safe
        return "filename*=utf-8''\(encoded)"
    }

    static func wrappedBase64(_ data: Data) -> String {
        data.base64EncodedString(options: [
            .lineLength76Characters,
            .endLineWithCarriageReturn,
            .endLineWithLineFeed
        ])
    }

    static func mimeType(forExtension ext: String) -> String {
        let types: [String: String] = [
            "pdf": "application/pdf", "zip": "application/zip", "json": "application/json",
            "xml": "application/xml", "txt": "text/plain", "csv": "text/csv", "md": "text/markdown",
            "html": "text/html", "htm": "text/html", "ics": "text/calendar",
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "svg": "image/svg+xml", "heic": "image/heic",
            "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav", "mp4": "video/mp4",
            "mov": "video/quicktime",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        ]
        return types[ext.lowercased()] ?? "application/octet-stream"
    }

    // MARK: - Headers

    /// Replaces CR and LF with spaces so a value can't start a new header.
    static func sanitizeHeaderValue(_ value: String) -> String {
        value.unicodeScalars
            .map { $0 == "\r" || $0 == "\n" ? " " : String($0) }
            .joined()
    }

    /// RFC 2047 `=?utf-8?B?…?=` encoding for non-ASCII text, split into
    /// encoded-words of at most 45 UTF-8 bytes (never splitting a character)
    /// and folded onto continuation lines. ASCII text is returned unchanged.
    static func encodeWordIfNeeded(_ text: String) -> String {
        guard !text.unicodeScalars.allSatisfy(\.isASCII) else { return text }

        var words: [String] = []
        var chunk = ""
        for character in text {
            if chunk.utf8.count + String(character).utf8.count > 45, !chunk.isEmpty {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words
            .map { "=?utf-8?B?\(Data($0.utf8).base64EncodedString())?=" }
            .joined(separator: "\r\n ")
    }

    /// Encodes non-ASCII display names in a comma-separated address list.
    /// ponytail: splits on commas, so a quoted display name containing a comma
    /// is not supported. Upgrade to a real RFC 5322 address parser if needed.
    static func encodeAddressList(_ list: String) -> String {
        let safe = sanitizeHeaderValue(list)
        guard !safe.unicodeScalars.allSatisfy(\.isASCII) else { return safe }

        return safe.split(separator: ",").map { rawEntry -> String in
            let entry = rawEntry.trimmingCharacters(in: .whitespaces)
            guard let open = entry.lastIndex(of: "<") else { return entry }

            var name = entry[..<open].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            let address = entry[open...]
            guard !name.isEmpty else { return String(address) }

            return "\(encodeWordIfNeeded(name)) \(address)"
        }.joined(separator: ", ")
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Domain of the sender address, or `himalaya-mcp.local` when unknown.
    static func messageIDDomain(from: String?) -> String {
        guard let from, let atSign = from.lastIndex(of: "@") else { return "himalaya-mcp.local" }

        let domain = from[from.index(after: atSign)...]
            .prefix { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return domain.isEmpty ? "himalaya-mcp.local" : String(domain)
    }
}
