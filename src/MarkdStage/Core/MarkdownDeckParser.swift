import Foundation

struct MarkdownDeckParser: Sendable {
    private static let defaultBackCover = "---\nlayout: backcover\n---\n"
    private static let nonInheritedKeys: Set<String> = ["layout", "page"]
    private static let unnumberedLayouts: Set<String> = ["title", "section", "backcover"]

    func parse(_ text: String, addBackCover: Bool = true) -> DeckDocument {
        let normalized = Self.normalize(text)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cursor = 0
        while cursor < lines.count, lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cursor += 1
        }

        var deckMetadata = OrderedMetadata()
        if let frontMatter = Self.readFrontMatter(lines, at: cursor) {
            deckMetadata = frontMatter.metadata
            cursor = frontMatter.end + 1
        }

        let parsedSlides = Self.splitSlides(lines, from: cursor)
        guard !parsedSlides.isEmpty else {
            return DeckDocument(slides: [], metadata: deckMetadata.dictionary, theme: "dark", themeFile: "")
        }

        var mergedSlides: [Slide] = []
        for (index, parsedSlide) in parsedSlides.enumerated() {
            var metadata = OrderedMetadata()
            for entry in deckMetadata.entries {
                if Self.nonInheritedKeys.contains(entry.normalizedKey),
                   !(index == 0 && entry.normalizedKey == "layout") {
                    continue
                }
                metadata.set(entry.key, value: entry.value)
            }
            for entry in parsedSlide.metadata.entries {
                metadata.set(entry.key, value: entry.value)
            }
            mergedSlides.append(Slide(metadata: metadata, body: parsedSlide.body))
        }

        let total = mergedSlides.filter { Self.layout(of: $0.metadata) != "backcover" }.count
        var ordinal = 0
        var fragments: [String] = []
        for var slide in mergedSlides {
            let layout = Self.layout(of: slide.metadata)
            if layout != "backcover" {
                ordinal += 1
            }
            if !Self.unnumberedLayouts.contains(layout) {
                if !slide.metadata.contains("page") {
                    slide.metadata.set("page", value: String(ordinal))
                }
                if !slide.metadata.contains("total") {
                    slide.metadata.set("total", value: String(total))
                }
            }
            fragments.append(Self.format(slide))
        }

        if addBackCover, !fragments.isEmpty {
            let lastMetadata = Self.fragmentMetadata(fragments[fragments.count - 1])
            if lastMetadata["layout"]?.lowercased() != "backcover" {
                fragments.append(Self.defaultBackCover)
            }
        }

        var theme = "dark"
        var themeFile = ""
        for fragment in fragments {
            let metadata = Self.fragmentMetadata(fragment)
            if let candidate = metadata["theme"], !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                theme = Self.normalizeTheme(candidate)
                themeFile = metadata["theme-file"] ?? ""
                break
            }
            if let candidate = metadata["theme-file"],
               !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                theme = "custom"
                themeFile = candidate
                break
            }
        }

        return DeckDocument(
            slides: fragments,
            metadata: deckMetadata.dictionary,
            theme: theme,
            themeFile: themeFile
        )
    }

    static func fragmentMetadata(_ markdown: String) -> [String: String] {
        let normalized = normalize(markdown)
            .drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" || $0 == "\u{FEFF}" })
        let value = String(normalized)
        guard value.hasPrefix("---\n") || value == "---" else { return [:] }

        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if isSeparator(line) { break }
            guard let separator = line.firstIndex(of: ":"), separator != line.startIndex else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            let parsedValue = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if !key.isEmpty {
                result[key.lowercased()] = parsedValue
            }
        }
        return result
    }

    private static func splitSlides(_ lines: [String], from cursor: Int) -> [Slide] {
        var slides: [Slide] = []
        var metadata = OrderedMetadata()
        var body: [String] = []
        var sawContent = false
        var fence: String?

        func flushedSlide() -> Slide? {
            let bodyText = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bodyText.isEmpty || !metadata.isEmpty else { return nil }
            return Slide(metadata: metadata, body: bodyText)
        }

        func reset() {
            metadata = OrderedMetadata()
            body = []
            sawContent = false
        }

        guard cursor < lines.count else { return [] }
        var index = cursor
        while index < lines.count {
            let line = lines[index]
            if let activeFence = fence {
                body.append(line)
                if closesFence(line, fence: activeFence) {
                    fence = nil
                }
                index += 1
                continue
            }

            if let openedFence = openedFence(in: line) {
                fence = openedFence
                body.append(line)
                sawContent = true
                index += 1
                continue
            }

            if isSeparator(line) {
                let previous = index > 0 ? lines[index - 1] : ""
                if sawContent, !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    body.append(line)
                    index += 1
                    continue
                }

                if let frontMatter = readFrontMatter(lines, at: index) {
                    if sawContent || !metadata.isEmpty {
                        if let slide = flushedSlide() { slides.append(slide) }
                        reset()
                    }
                    metadata = frontMatter.metadata
                    index = frontMatter.end + 1
                    continue
                }

                if let slide = flushedSlide() { slides.append(slide) }
                reset()
                index += 1
                continue
            }

            body.append(line)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sawContent = true
            }
            index += 1
        }

        if let slide = flushedSlide() { slides.append(slide) }
        return slides
    }

    private static func readFrontMatter(_ lines: [String], at start: Int) -> FrontMatter? {
        guard start >= 0, start < lines.count, isSeparator(lines[start]) else { return nil }
        var metadata = OrderedMetadata()
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if isSeparator(line) {
                return metadata.isEmpty ? nil : FrontMatter(metadata: metadata, end: index)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard let match = firstMatch(
                #"^([A-Za-z][A-Za-z0-9_-]*)[ \t]*:(.*)$"#,
                in: line,
                captures: 2
            ) else {
                return nil
            }
            metadata.set(match[0], value: match[1].trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return nil
    }

    private static func format(_ slide: Slide) -> String {
        guard !slide.metadata.isEmpty else { return slide.body }
        var lines = ["---"]
        lines.append(contentsOf: slide.metadata.entries.map {
            $0.value.isEmpty ? "\($0.key):" : "\($0.key): \($0.value)"
        })
        lines.append("---")
        let frontMatter = lines.joined(separator: "\n")
        return slide.body.isEmpty ? frontMatter : "\(frontMatter)\n\(slide.body)"
    }

    private static func layout(of metadata: OrderedMetadata) -> String {
        metadata.value(for: "layout")?.lowercased() ?? ""
    }

    private static func normalize(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if value.first == "\u{FEFF}" {
            value.removeFirst()
        }
        return value
    }

    private static func normalizeTheme(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["light", "microsoft", "custom"].contains(normalized) ? normalized : "dark"
    }

    private static func isSeparator(_ line: String) -> Bool {
        line.range(of: #"^[ \t]{0,3}-{3,}[ \t]*$"#, options: .regularExpression) != nil
    }

    private static func openedFence(in line: String) -> String? {
        firstMatch(#"^([ \t]{0,3})(`{3,}|~{3,})[ \t]*([^\s`~]*)[ \t]*$"#, in: line, captures: 3)?[1]
    }

    private static func closesFence(_ line: String, fence: String) -> Bool {
        guard let character = fence.first else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: String(character))
        return line.range(
            of: #"^[ \t]{0,3}\#(escaped){\#(fence.count),}[ \t]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func firstMatch(
        _ pattern: String,
        in value: String,
        captures: Int
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ) else {
            return nil
        }
        return (1...captures).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return "" }
            return String(value[swiftRange])
        }
    }
}

private struct OrderedMetadata: Sendable {
    struct Entry: Sendable {
        let key: String
        var value: String
        var normalizedKey: String { key.lowercased() }
    }

    private var order: [String] = []
    private var storage: [String: Entry] = [:]

    var isEmpty: Bool { order.isEmpty }
    var entries: [Entry] { order.compactMap { storage[$0] } }
    var dictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
    }

    mutating func set(_ key: String, value: String) {
        let normalized = key.lowercased()
        if var existing = storage[normalized] {
            existing.value = value
            storage[normalized] = existing
        } else {
            order.append(normalized)
            storage[normalized] = Entry(key: key, value: value)
        }
    }

    func contains(_ key: String) -> Bool {
        storage[key.lowercased()] != nil
    }

    func value(for key: String) -> String? {
        storage[key.lowercased()]?.value
    }
}

private struct FrontMatter: Sendable {
    let metadata: OrderedMetadata
    let end: Int
}

private struct Slide: Sendable {
    var metadata: OrderedMetadata
    let body: String
}
