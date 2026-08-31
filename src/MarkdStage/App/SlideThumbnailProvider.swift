import AppKit
import PDFKit

@MainActor
protocol DeckPDFRendering: AnyObject {
    func render(
        completion: @escaping @MainActor (Result<PDFDocument, Error>) -> Void
    )
    func cancel()
    func shutdown()
}

extension DeckPDFRenderer: DeckPDFRendering {}

@MainActor
protocol SlideThumbnailProviding: AnyObject {
    func render(
        deckVersion: Int64,
        slideCount: Int,
        onThumbnail: @escaping (Int64, Int, NSImage) -> Void,
        completion: @escaping (Int64, Result<Void, Error>) -> Void
    )
    func cancel()
    func shutdown()
    func cachedDocument(deckVersion: Int64) -> PDFDocument?
}

@MainActor
final class SlideThumbnailProvider: SlideThumbnailProviding {
    enum GenerationError: LocalizedError, Equatable {
        case invalidSlideCount(Int)
        case pageCountMismatch(expected: Int, actual: Int)
        case missingPage(Int)

        var errorDescription: String? {
            switch self {
            case let .invalidSlideCount(count):
                "Thumbnail generation received an invalid slide count: \(count)."
            case let .pageCountMismatch(expected, actual):
                "Thumbnail PDF contained \(actual) pages; expected \(expected)."
            case let .missingPage(index):
                "Thumbnail PDF page \(index + 1) could not be read."
            }
        }
    }

    static let thumbnailSize = NSSize(width: 320, height: 180)

    private struct CacheKey: Hashable {
        let deckVersion: Int64
        let index: Int
    }

    private struct Generation {
        let token: UUID
        let deckVersion: Int64
        let slideCount: Int
        let renderer: any DeckPDFRendering
        let onThumbnail: (Int64, Int, NSImage) -> Void
        let completion: (Int64, Result<Void, Error>) -> Void
    }

    private let rendererFactory: () -> any DeckPDFRendering
    private let cacheLimit: Int
    private var renderer: (any DeckPDFRendering)?
    private var activeGeneration: Generation?
    private var acceptedRendererTokens: Set<UUID> = []
    private var cache: [CacheKey: NSImage] = [:]
    private var cacheOrder: [CacheKey] = []
    private var documentVersion: Int64?
    private var document: PDFDocument?

    init(parentWindow: NSWindow?, baseURL: URL) {
        rendererFactory = { [weak parentWindow] in
            DeckPDFRenderer(parentWindow: parentWindow, baseURL: baseURL)
        }
        cacheLimit = 256
    }

    init(
        rendererFactory: @escaping () -> any DeckPDFRendering,
        cacheLimit: Int = 256
    ) {
        self.rendererFactory = rendererFactory
        self.cacheLimit = max(1, cacheLimit)
    }

    func render(
        deckVersion: Int64,
        slideCount: Int,
        onThumbnail: @escaping (Int64, Int, NSImage) -> Void,
        completion: @escaping (Int64, Result<Void, Error>) -> Void
    ) {
        abandonActiveGeneration()

        guard slideCount >= 0 else {
            completion(
                deckVersion,
                .failure(GenerationError.invalidSlideCount(slideCount))
            )
            return
        }

        let renderer = self.renderer ?? rendererFactory()
        self.renderer = renderer
        let token = UUID()
        acceptedRendererTokens.removeAll(keepingCapacity: true)
        activeGeneration = Generation(
            token: token,
            deckVersion: deckVersion,
            slideCount: slideCount,
            renderer: renderer,
            onThumbnail: onThumbnail,
            completion: completion
        )
        renderer.render { [weak self] result in
            self?.rendererDidFinish(result, token: token)
        }
    }

    func cancel() {
        guard let generation = activeGeneration else { return }
        activeGeneration = nil
        acceptedRendererTokens.remove(generation.token)
        generation.renderer.cancel()
        generation.completion(generation.deckVersion, .success(()))
    }

    func shutdown() {
        activeGeneration = nil
        acceptedRendererTokens.removeAll()
        renderer?.shutdown()
        renderer = nil
        invalidateCache()
    }

    func cachedImage(deckVersion: Int64, index: Int) -> NSImage? {
        let key = CacheKey(deckVersion: deckVersion, index: index)
        guard let image = cache[key] else { return nil }
        touch(key)
        return image
    }

    func cachedDocument(deckVersion: Int64) -> PDFDocument? {
        documentVersion == deckVersion ? document : nil
    }

    func invalidateCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        documentVersion = nil
        document = nil
    }

    func invalidateCache(deckVersion: Int64) {
        cache = cache.filter { $0.key.deckVersion != deckVersion }
        cacheOrder.removeAll { $0.deckVersion == deckVersion }
        if documentVersion == deckVersion {
            documentVersion = nil
            document = nil
        }
    }

    private func rendererDidFinish(
        _ result: Result<PDFDocument, Error>,
        token: UUID
    ) {
        guard let generation = activeGeneration,
              generation.token == token,
              acceptedRendererTokens.insert(token).inserted else {
            return
        }

        switch result {
        case let .failure(error):
            finish(
                generation,
                with: error is CancellationError ? .success(()) : .failure(error)
            )
        case let .success(document):
            generateThumbnails(from: document, for: generation)
        }
    }

    private func generateThumbnails(
        from document: PDFDocument,
        for generation: Generation
    ) {
        guard document.pageCount == generation.slideCount else {
            documentVersion = nil
            self.document = nil
            finish(
                generation,
                with: .failure(
                    GenerationError.pageCountMismatch(
                        expected: generation.slideCount,
                        actual: document.pageCount
                    )
                )
            )
            return
        }
        documentVersion = generation.deckVersion
        self.document = document

        generateThumbnail(
            at: 0,
            from: document,
            for: generation
        )
    }

    private func generateThumbnail(
        at index: Int,
        from document: PDFDocument,
        for generation: Generation
    ) {
        guard activeGeneration?.token == generation.token else { return }
        guard index < generation.slideCount else {
            finish(generation, with: .success(()))
            return
        }
        guard let page = document.page(at: index) else {
            finish(
                generation,
                with: .failure(GenerationError.missingPage(index))
            )
            return
        }

        let key = CacheKey(
            deckVersion: generation.deckVersion,
            index: index
        )
        let image: NSImage
        if let cached = cache[key] {
            touch(key)
            image = cached
        } else {
            image = Self.rasterize(page)
            insert(image, for: key)
        }
        generation.onThumbnail(generation.deckVersion, index, image)

        DispatchQueue.main.async { [weak self] in
            self?.generateThumbnail(
                at: index + 1,
                from: document,
                for: generation
            )
        }
    }

    private func finish(
        _ generation: Generation,
        with result: Result<Void, Error>
    ) {
        guard activeGeneration?.token == generation.token else { return }
        activeGeneration = nil
        acceptedRendererTokens.remove(generation.token)
        generation.completion(generation.deckVersion, result)
    }

    private func abandonActiveGeneration() {
        guard let generation = activeGeneration else { return }
        activeGeneration = nil
        acceptedRendererTokens.remove(generation.token)
        generation.renderer.cancel()
    }

    private func insert(_ image: NSImage, for key: CacheKey) {
        cache[key] = image
        touch(key)
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func touch(_ key: CacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private static func rasterize(_ page: PDFPage) -> NSImage {
        let size = thumbnailSize
        let pageImage = page.thumbnail(of: size, for: .mediaBox)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let destination = aspectFitRect(
            contentSize: pageImage.size,
            containerSize: size
        )
        pageImage.draw(
            in: destination,
            from: NSRect(origin: .zero, size: pageImage.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        return image
    }

    private static func aspectFitRect(
        contentSize: NSSize,
        containerSize: NSSize
    ) -> NSRect {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return NSRect(origin: .zero, size: containerSize)
        }
        let scale = min(
            containerSize.width / contentSize.width,
            containerSize.height / contentSize.height
        )
        let size = NSSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return NSRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
