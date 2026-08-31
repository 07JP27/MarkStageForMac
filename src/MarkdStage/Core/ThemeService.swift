import Foundation

struct ThemeService: Sendable {
    private let themeFileMaxBytes = 64 * 1024
    private let themeAssetMaxBytes = 2 * 1024 * 1024

    func load(document: DeckDocument, sourceURL: URL, workspaceRoot: URL) throws -> ThemeState {
        guard document.theme.caseInsensitiveCompare("custom") == .orderedSame else {
            return ThemeState(name: document.theme)
        }
        guard !document.themeFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeckLoadError(message: "Custom theme requires a theme-file value.")
        }
        guard let themeURL = resolveThemeFile(
            sourceURL: sourceURL,
            workspaceRoot: workspaceRoot,
            relativePath: document.themeFile
        ) else {
            throw DeckLoadError(message: "Custom theme was not found: \(document.themeFile)")
        }
        guard Self.fileSize(themeURL) <= themeFileMaxBytes else {
            throw DeckLoadError(message: "Custom theme CSS must be 64 KiB or smaller.")
        }
        let source = try String(contentsOf: themeURL, encoding: .utf8)
        let css = try parseThemeVariables(source)
        let themeDirectory = themeURL.deletingLastPathComponent()
        let metadataURL = themeDirectory.appendingPathComponent("theme.json")
        var metadataJSON = ""
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            guard PathSecurity.isFileURL(metadataURL, containedIn: themeDirectory),
                  Self.fileSize(metadataURL) <= themeFileMaxBytes else {
                throw DeckLoadError(message: "Custom theme metadata must stay inside its theme folder and be 64 KiB or smaller.")
            }
            metadataJSON = try validateAndMapMetadata(
                Data(contentsOf: metadataURL),
                themeDirectory: themeDirectory
            )
        }
        return ThemeState(
            name: "custom",
            css: css,
            metadataJSON: metadataJSON,
            assetRoot: themeDirectory
        )
    }

    private func resolveThemeFile(
        sourceURL: URL,
        workspaceRoot: URL,
        relativePath: String
    ) -> URL? {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\0") else { return nil }
        let roots = [sourceURL.deletingLastPathComponent(), workspaceRoot]
        for root in roots {
            if let resolved = PathSecurity.resolveFile(in: root, relativePath: relativePath),
               PathSecurity.isFileURL(resolved, containedIn: workspaceRoot) {
                return resolved
            }
        }
        return nil
    }

    private func parseThemeVariables(_ css: String) throws -> String {
        var body = css.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix(":root") {
            guard let expression = try? NSRegularExpression(pattern: #"^:root\s*\{([\s\S]*)\}\s*$"#),
                  let match = expression.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  let range = Range(match.range(at: 1), in: body) else {
                throw DeckLoadError(message: "Custom theme CSS must contain only a complete :root block.")
            }
            body = String(body[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var values: [String] = []
        for declaration in body.split(separator: ";", omittingEmptySubsequences: false) {
            let item = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }
            guard let separator = item.firstIndex(of: ":") else {
                throw DeckLoadError(message: "Custom theme CSS may contain only custom property declarations.")
            }
            let name = item[..<separator].trimmingCharacters(in: .whitespaces)
            let value = item[item.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^--[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                  !value.isEmpty,
                  value.rangeOfCharacter(from: CharacterSet(charactersIn: "{}")) == nil,
                  value.range(
                    of: #"</?style\b|@import\b|expression\s*\(|javascript\s*:|url\s*\("#,
                    options: [.regularExpression, .caseInsensitive]
                  ) == nil else {
                throw DeckLoadError(message: "Custom theme CSS contains an unsafe declaration.")
            }
            values.append("\(name):\(value);")
        }
        guard !values.isEmpty else {
            throw DeckLoadError(message: "Custom theme CSS must define at least one custom property.")
        }
        return values.joined()
    }

    private func validateAndMapMetadata(_ data: Data, themeDirectory: URL) throws -> String {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DeckLoadError(message: "Custom theme metadata is not valid JSON.")
        }
        guard var metadata = raw as? [String: Any],
              metadata["version"] as? Int == 1 else {
            throw DeckLoadError(message: "Custom theme metadata version must be 1.")
        }
        try validateOnlyKeys(metadata, allowed: ["$schema", "version", "cover", "backcover"])
        if let cover = metadata["cover"] {
            metadata["cover"] = try validateSection(
                cover,
                allowed: ["background", "logo"],
                themeDirectory: themeDirectory
            )
        }
        if let backcover = metadata["backcover"] {
            metadata["backcover"] = try validateSection(
                backcover,
                allowed: ["logo", "copyright"],
                themeDirectory: themeDirectory
            )
        }
        let mapped = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        return String(decoding: mapped, as: UTF8.self)
    }

    private func validateSection(
        _ value: Any,
        allowed: Set<String>,
        themeDirectory: URL
    ) throws -> [String: Any] {
        guard var section = value as? [String: Any] else {
            throw DeckLoadError(message: "Custom theme metadata sections must be objects.")
        }
        try validateOnlyKeys(section, allowed: allowed)
        for key in section.keys {
            if key == "copyright" {
                guard section[key] is String else {
                    throw DeckLoadError(message: "Theme copyright must be a string.")
                }
                continue
            }
            guard var image = section[key] as? [String: Any] else {
                throw DeckLoadError(message: "Theme image entries must be objects.")
            }
            try validateOnlyKeys(image, allowed: ["image", "alt"])
            guard let relativePath = image["image"] as? String,
                  relativePath.range(
                    of: #"^assets/(?:[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)*/)*[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)*\.(?:svg|png|webp|jpg|jpeg)$"#,
                    options: [.regularExpression, .caseInsensitive]
                  ) != nil,
                  let assetURL = PathSecurity.resolveFile(in: themeDirectory, relativePath: relativePath)
            else {
                throw DeckLoadError(message: "Invalid custom theme asset path.")
            }
            guard Self.fileSize(assetURL) <= themeAssetMaxBytes else {
                throw DeckLoadError(message: "Custom theme assets must be 2 MiB or smaller.")
            }
            if key == "logo" {
                guard let alt = image["alt"] as? String,
                      !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DeckLoadError(message: "Theme logos require non-empty alt text.")
                }
            } else if let alt = image["alt"], !(alt is String) {
                throw DeckLoadError(message: "Theme image alt text must be a string.")
            }
            image["image"] = "theme-assets/\(relativePath.replacingOccurrences(of: "\\", with: "/"))"
            section[key] = image
        }
        return section
    }

    private func validateOnlyKeys(_ value: [String: Any], allowed: Set<String>) throws {
        if let unsupported = value.keys.first(where: { !allowed.contains($0) }) {
            throw DeckLoadError(message: "Custom theme metadata key is not supported: \(unsupported)")
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
    }
}
