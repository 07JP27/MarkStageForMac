import Foundation

enum SlideTitleDeriver {
    private static let untitled = "(Untitled)"
    private static let maximumLength = 40

    static func derive(_ markdown: String?) -> String {
        let body = SpeakerNotesExtractor.remove(from: removeLeadingFrontMatter(markdown ?? ""))
        var fallback = ""
        var fence: String?
        for rawLine in body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        {
            let sourceLine = String(rawLine)
            if let activeFence = fence {
                if SpeakerNotesExtractor.closesFence(sourceLine, fence: activeFence) {
                    fence = nil
                }
                continue
            }
            if let openedFence = SpeakerNotesExtractor.openedFence(in: sourceLine) {
                fence = openedFence
                continue
            }

            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let title = plainText(from: heading)
                if !title.isEmpty {
                    return trimTitle(title)
                }
            }
            if fallback.isEmpty {
                fallback = plainText(from: line)
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

    private static func plainText(from markdown: String) -> String {
        var text = markdown.replacingOccurrences(
            of: #"(?i)<br\s*/?\s*>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"[*_`>#~]"#,
            with: "",
            options: .regularExpression
        )
        for (entity, value) in [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimTitle(_ text: String) -> String {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return untitled }
        guard stripped.count > maximumLength else { return stripped }
        return String(stripped.prefix(maximumLength)) + "…"
    }
}
