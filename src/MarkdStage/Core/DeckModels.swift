import Foundation

struct DeckDocument: Equatable, Sendable {
    let slides: [String]
    let metadata: [String: String]
    let theme: String
    let themeFile: String
}

struct ThemeState: Equatable, Sendable {
    let name: String
    let css: String
    let metadataJSON: String
    let assetRoot: URL?

    init(
        name: String,
        css: String = "",
        metadataJSON: String = "",
        assetRoot: URL? = nil
    ) {
        self.name = name
        self.css = css
        self.metadataJSON = metadataJSON
        self.assetRoot = assetRoot
    }
}

struct LoadedDeck: Equatable, Sendable {
    let document: DeckDocument
    let theme: ThemeState
    let sourceURL: URL
    let workspaceRoot: URL
}

struct PresentationSnapshot: Equatable, Sendable {
    let slides: [String]
    let index: Int
    let version: Int64
    let deckVersion: Int64
    let sourceURL: URL?
    let workspaceRoot: URL?
    let theme: ThemeState

    var total: Int { slides.count }

    var currentMarkdown: String {
        guard !slides.isEmpty else { return "" }
        return slides[min(max(index, 0), slides.count - 1)]
    }

    func markdown(atOffset offset: Int) -> String {
        guard !slides.isEmpty else { return "" }
        let target = min(max(index + offset, 0), slides.count - 1)
        return slides[target]
    }

    var hasNext: Bool {
        index + 1 < slides.count
    }
}

struct DeckLoadError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? { message }
}
