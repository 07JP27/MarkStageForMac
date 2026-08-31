import Foundation

struct DeckLoader: Sendable {
    private let maximumBytes = 2 * 1024 * 1024
    private let parser = MarkdownDeckParser()
    private let themeService = ThemeService()

    func load(_ url: URL) throws -> LoadedDeck {
        let sourceURL = PathSecurity.canonicalURL(url)
        let extensionName = sourceURL.pathExtension.lowercased()
        guard extensionName == "md" || extensionName == "markdown" else {
            throw DeckLoadError(message: "Select a .md or .markdown file.")
        }

        let text = try readStable(sourceURL)
        let document = parser.parse(text)
        guard !document.slides.isEmpty else {
            throw DeckLoadError(message: "Markdown is empty.")
        }

        let workspaceRoot = findWorkspaceRoot(sourceURL)
        let theme = try themeService.load(
            document: document,
            sourceURL: sourceURL,
            workspaceRoot: workspaceRoot
        )
        return LoadedDeck(
            document: document,
            theme: theme,
            sourceURL: sourceURL,
            workspaceRoot: workspaceRoot
        )
    }

    private func readStable(_ url: URL) throws -> String {
        for attempt in 0..<5 {
            do {
                let before = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard let size = before.fileSize else {
                    throw DeckLoadError(message: "Markdown was not found.")
                }
                guard size <= maximumBytes else {
                    throw DeckLoadError(message: "Markdown must be 2 MiB or smaller.")
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                Thread.sleep(forTimeInterval: 0.04)
                let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard before.fileSize == after.fileSize,
                      before.contentModificationDate == after.contentModificationDate else {
                    throw CocoaError(.fileReadUnknown)
                }
                return String(decoding: data, as: UTF8.self)
            } catch let error as DeckLoadError {
                throw error
            } catch {
                if attempt < 4 {
                    Thread.sleep(forTimeInterval: 0.05 * Double(attempt + 1))
                }
            }
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        throw DeckLoadError(
            message: exists ? "Markdown could not be read." : "Markdown was not found."
        )
    }

    private func findWorkspaceRoot(_ sourceURL: URL) -> URL {
        var directory = sourceURL.deletingLastPathComponent()
        while directory.path != "/" {
            let gitURL = directory.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                return PathSecurity.canonicalURL(directory)
            }
            directory.deleteLastPathComponent()
        }
        return PathSecurity.canonicalURL(sourceURL.deletingLastPathComponent())
    }
}
