/// Renders file paths as himalaya MML (MIME Meta Language) `<#part>` directives.
///
/// himalaya has no `--attachment` flag; attachments are expressed inline in the
/// message body/template and compiled to MIME parts when the message is sent.
enum MMLAttachment {
    /// One `<#part>` directive per path, joined by newlines. Empty string for no paths.
    static func directives(for paths: [String]) -> String {
        paths
            .map { #"<#part filename="\#($0)" disposition=attachment><#/part>"# }
            .joined(separator: "\n")
    }

    /// Appends attachment directives to `body`, separated by a blank line. Returns
    /// `body` unchanged when there are no attachments.
    static func appended(to body: String, paths: [String]) -> String {
        guard !paths.isEmpty else { return body }

        return body + "\n\n" + directives(for: paths)
    }
}
