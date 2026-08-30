import Foundation

enum SlideTitleDeriver {
    private static let untitled = "(Untitled)"
    private static let maximumLength = 40

    static func derive(_ markdown: String?) -> String {
        let body = SpeakerNotesExtractor.remove(from: removeLeadingFrontMatter(markdown ?? ""))
        var fallback = ""
        for rawLine in body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let range = line.range(
                of: #"^#{1,6}\s+(.*\S)\s*$"#,
                options: .regularExpression
            ) {
                let matched = String(line[range])
                let heading = matched.replacingOccurrences(
                    of: #"^#{1,6}\s+"#,
                    with: "",
                    options: .regularExpression
                )
                return trimTitle(heading)
            }
            if fallback.isEmpty {
                fallback = line
            }
        }
        return fallback.isEmpty ? untitled : trimTitle(fallback)
    }

    private static func removeLeadingFrontMatter(_ markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" || $0 == "\u{FEFF}" })
        guard trimmed.hasPrefix("---\n") || trimmed == "---" else { return markdown }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        for index in lines.indices.dropFirst() where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            return lines[(index + 1)...].joined(separator: "\n")
        }
        return markdown
    }

    private static func trimTitle(_ text: String) -> String {
        var stripped = text.replacingOccurrences(
            of: #"[*_`>#~]"#,
            with: "",
            options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return untitled }
        guard stripped.count > maximumLength else { return stripped }
        return String(stripped.prefix(maximumLength)) + "…"
    }
}
