import Foundation

enum SpeakerNotesExtractor {
    static func extract(_ markdown: String?) -> String {
        parse(markdown).notes
    }

    static func remove(from markdown: String?) -> String {
        parse(markdown).markdown
    }

    private static func parse(_ markdown: String?) -> (markdown: String, notes: String) {
        var notes: [String] = []
        var output: [String] = []
        let lines = normalize(markdown ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var fence: String?
        var comment: String?

        for line in lines {
            if comment == nil, let activeFence = fence {
                if closesFence(line, fence: activeFence) {
                    fence = nil
                }
                output.append(line)
                continue
            }

            if comment == nil, let opened = openedFence(in: line) {
                fence = opened
                output.append(line)
                continue
            }

            var visible = ""
            var cursor = line.startIndex
            while cursor <= line.endIndex {
                if comment == nil {
                    guard let start = line.range(of: "<!--", range: cursor..<line.endIndex)?.lowerBound else {
                        visible += String(line[cursor...])
                        break
                    }
                    let before = visible + String(line[cursor..<start])
                    if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || before.count > 3 {
                        visible += String(line[cursor...])
                        break
                    }
                    visible = before
                    comment = ""
                    cursor = line.index(start, offsetBy: 4)
                }

                guard let end = line.range(of: "-->", range: cursor..<line.endIndex) else {
                    comment! += String(line[cursor...]) + "\n"
                    break
                }
                comment! += String(line[cursor..<end.lowerBound])
                addNote(comment ?? "", to: &notes)
                comment = nil
                cursor = end.upperBound
                if cursor == line.endIndex {
                    break
                }
            }
            output.append(visible)
        }

        return (output.joined(separator: "\n"), notes.joined(separator: "\n\n"))
    }

    private static func addNote(_ candidate: String, to notes: inout [String]) {
        let note = normalizeIndentation(candidate)
        guard !note.isEmpty,
              note.range(of: #"^slide-size[ \t]*:"#, options: [.regularExpression, .caseInsensitive]) == nil
        else {
            return
        }
        notes.append(note)
    }

    private static func normalizeIndentation(_ value: String) -> String {
        var lines = normalize(value)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return "" }
        let indentation = lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(leadingWhitespaceCount)
            .min() ?? 0
        return lines.map { line in
            String(line.dropFirst(min(indentation, line.count)))
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func openedFence(in line: String) -> String? {
        let indentation = leadingWhitespaceCount(line)
        guard indentation <= 3 else { return nil }
        let content = line.dropFirst(indentation)
        guard let marker = content.first, marker == "`" || marker == "~" else { return nil }
        let count = content.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = content.dropFirst(count)
        guard marker != "`" || !info.contains("`") else { return nil }
        return String(repeating: marker, count: count)
    }

    static func closesFence(_ line: String, fence: String) -> Bool {
        let indentation = leadingWhitespaceCount(line)
        guard indentation <= 3 else { return false }
        let trimmed = line.dropFirst(indentation).trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= fence.count, trimmed.first == fence.first else { return false }
        let count = trimmed.prefix(while: { $0 == fence.first }).count
        return count >= fence.count &&
            trimmed.dropFirst(count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func leadingWhitespaceCount(_ value: String) -> Int {
        value.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
