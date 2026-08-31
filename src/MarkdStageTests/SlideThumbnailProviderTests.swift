import AppKit
import PDFKit
import XCTest
@testable import MarkdStage

@MainActor
final class SlideThumbnailProviderTests: XCTestCase {
    func testOneRendererProducesOneAspectCorrectImagePerPDFPage() async throws {
        let (provider, factory) = makeProvider()
        var thumbnails: [(Int64, Int, NSImage)] = []
        var completions: [(Int64, Result<Void, Error>)] = []
        let completed = expectation(description: "Thumbnails generated")

        provider.render(
            deckVersion: 41,
            slideCount: 3,
            onThumbnail: { thumbnails.append(($0, $1, $2)) },
            completion: {
                completions.append(($0, $1))
                completed.fulfill()
            }
        )

        XCTAssertEqual(factory.renderers.count, 1)
        XCTAssertEqual(factory.renderers[0].renderCallCount, 1)
        factory.renderers[0].emit(.success(try makePDF(pageCount: 3)))
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(thumbnails.map(\.0), [41, 41, 41])
        XCTAssertEqual(thumbnails.map(\.1), [0, 1, 2])
        XCTAssertEqual(completions.count, 1)
        XCTAssertNoThrow(try completions[0].1.get())
        XCTAssertEqual(provider.cachedDocument(deckVersion: 41)?.pageCount, 3)
        for thumbnail in thumbnails.map(\.2) {
            XCTAssertEqual(thumbnail.size.width, 320, accuracy: 0.001)
            XCTAssertEqual(thumbnail.size.height, 180, accuracy: 0.001)
            XCTAssertEqual(
                thumbnail.size.width / thumbnail.size.height,
                16.0 / 9.0,
                accuracy: 0.001
            )
        }
    }

    func testCacheIsKeyedAndCanBeInvalidatedByDeckVersion() throws {
        let (provider, factory) = makeProvider()
        var versionOneImage: NSImage?
        var versionTwoImage: NSImage?

        provider.render(
            deckVersion: 1,
            slideCount: 1,
            onThumbnail: { _, _, image in versionOneImage = image },
            completion: { _, _ in }
        )
        factory.renderers[0].emit(.success(try makePDF(pageCount: 1)))

        provider.render(
            deckVersion: 2,
            slideCount: 1,
            onThumbnail: { _, _, image in versionTwoImage = image },
            completion: { _, _ in }
        )
        XCTAssertEqual(factory.renderers.count, 1)
        XCTAssertEqual(factory.renderers[0].renderCallCount, 2)
        factory.renderers[0].emit(
            .success(try makePDF(pageCount: 1)),
            callIndex: 1
        )

        XCTAssertTrue(provider.cachedImage(deckVersion: 1, index: 0) === versionOneImage)
        XCTAssertTrue(provider.cachedImage(deckVersion: 2, index: 0) === versionTwoImage)
        XCTAssertNil(provider.cachedImage(deckVersion: 1, index: 1))

        provider.invalidateCache(deckVersion: 1)
        XCTAssertNil(provider.cachedImage(deckVersion: 1, index: 0))
        XCTAssertNotNil(provider.cachedImage(deckVersion: 2, index: 0))

        provider.invalidateCache()
        XCTAssertNil(provider.cachedImage(deckVersion: 2, index: 0))
    }

    func testNewGenerationCancelsAndIgnoresStaleRendererCallbacks() async throws {
        let (provider, factory) = makeProvider()
        var thumbnailVersions: [Int64] = []
        var completionVersions: [Int64] = []
        let completed = expectation(description: "Current generation completed")

        provider.render(
            deckVersion: 10,
            slideCount: 1,
            onThumbnail: { version, _, _ in thumbnailVersions.append(version) },
            completion: { version, _ in completionVersions.append(version) }
        )
        provider.render(
            deckVersion: 11,
            slideCount: 1,
            onThumbnail: { version, _, _ in thumbnailVersions.append(version) },
            completion: { version, _ in
                completionVersions.append(version)
                completed.fulfill()
            }
        )

        XCTAssertEqual(factory.renderers.count, 1)
        XCTAssertEqual(factory.renderers[0].cancelCallCount, 1)
        factory.renderers[0].emit(
            .success(try makePDF(pageCount: 1)),
            callIndex: 0
        )
        XCTAssertTrue(thumbnailVersions.isEmpty)
        XCTAssertTrue(completionVersions.isEmpty)

        factory.renderers[0].emit(
            .success(try makePDF(pageCount: 1)),
            callIndex: 1
        )
        factory.renderers[0].emit(
            .success(try makePDF(pageCount: 1)),
            callIndex: 1
        )
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(thumbnailVersions, [11])
        XCTAssertEqual(completionVersions, [11])
    }

    func testCancellationCompletesOnceWithoutSurfacingAnError() {
        let (provider, factory) = makeProvider()
        var results: [Result<Void, Error>] = []

        provider.render(
            deckVersion: 7,
            slideCount: 1,
            onThumbnail: { _, _, _ in XCTFail("Cancelled render produced a thumbnail") },
            completion: { _, result in results.append(result) }
        )
        provider.cancel()
        factory.renderers[0].emit(.failure(CancellationError()))

        XCTAssertEqual(factory.renderers[0].cancelCallCount, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertNoThrow(try results[0].get())
    }

    func testPageCountMismatchFailsWithoutProducingImages() throws {
        let (provider, factory) = makeProvider()
        var thumbnailCount = 0
        var result: Result<Void, Error>?

        provider.render(
            deckVersion: 3,
            slideCount: 2,
            onThumbnail: { _, _, _ in thumbnailCount += 1 },
            completion: { _, value in result = value }
        )
        factory.renderers[0].emit(.success(try makePDF(pageCount: 1)))

        XCTAssertEqual(thumbnailCount, 0)
        XCTAssertNil(provider.cachedDocument(deckVersion: 3))
        XCTAssertThrowsError(try XCTUnwrap(result).get()) { error in
            XCTAssertEqual(
                error as? SlideThumbnailProvider.GenerationError,
                .pageCountMismatch(expected: 2, actual: 1)
            )
        }
    }

    private func makeProvider() -> (
        SlideThumbnailProvider,
        FakePDFRendererFactory
    ) {
        let factory = FakePDFRendererFactory()
        let provider = SlideThumbnailProvider(rendererFactory: {
            factory.makeRenderer()
        })
        return (provider, factory)
    }

    private func makePDF(pageCount: Int) throws -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 1_600, height: 900))
            image.lockFocus()
            NSColor(
                calibratedHue: CGFloat(index) / CGFloat(max(pageCount, 1)),
                saturation: 0.4,
                brightness: 0.8,
                alpha: 1
            ).setFill()
            NSRect(origin: .zero, size: image.size).fill()
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}

@MainActor
private final class FakePDFRendererFactory {
    private(set) var renderers: [FakePDFRenderer] = []

    func makeRenderer() -> FakePDFRenderer {
        let renderer = FakePDFRenderer()
        renderers.append(renderer)
        return renderer
    }
}

@MainActor
private final class FakePDFRenderer: DeckPDFRendering {
    private var completions: [
        (@MainActor (Result<PDFDocument, Error>) -> Void)
    ] = []
    private(set) var renderCallCount = 0
    private(set) var cancelCallCount = 0

    func render(
        completion: @escaping @MainActor (Result<PDFDocument, Error>) -> Void
    ) {
        renderCallCount += 1
        completions.append(completion)
    }

    func cancel() {
        cancelCallCount += 1
    }

    func shutdown() {
        cancelCallCount += 1
    }

    func emit(
        _ result: Result<PDFDocument, Error>,
        callIndex: Int? = nil
    ) {
        let index = callIndex ?? (completions.count - 1)
        guard completions.indices.contains(index) else { return }
        completions[index](result)
    }
}
