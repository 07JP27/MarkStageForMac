import AppKit
import XCTest
@testable import MarkdStage

@MainActor
final class SlideThumbnailSidebarTests: XCTestCase {
    func testEmptyStateAndItemCount() throws {
        let sidebar = makeSidebar()

        XCTAssertEqual(sidebar.itemCount, 0)
        XCTAssertNil(sidebar.currentSelection)
        XCTAssertTrue(visibleLabels(in: sidebar).contains("No slides"))

        sidebar.updateSlides(
            titles: ["Opening", "Architecture", "Questions"],
            deckVersion: 1
        )

        XCTAssertEqual(sidebar.itemCount, 3)
        XCTAssertFalse(visibleLabels(in: sidebar).contains("No slides"))

        sidebar.clear()
        XCTAssertEqual(sidebar.itemCount, 0)
        XCTAssertNil(sidebar.currentSelection)
        XCTAssertTrue(visibleLabels(in: sidebar).contains("No slides"))
    }

    func testItemsExposeOneSlideAccessibilityLabel() throws {
        let sidebar = makeSidebar()
        sidebar.updateSlides(titles: ["Opening", ""], deckVersion: 1)
        var activated: [Int] = []
        sidebar.onSelectIndex = { activated.append($0) }
        let collectionView = try collectionView(in: sidebar)

        let first = try XCTUnwrap(
            sidebar.collectionView(
                collectionView,
                itemForRepresentedObjectAt: IndexPath(item: 0, section: 0)
            ) as? SlideThumbnailCollectionItem
        )
        let second = try XCTUnwrap(
            sidebar.collectionView(
                collectionView,
                itemForRepresentedObjectAt: IndexPath(item: 1, section: 0)
            ) as? SlideThumbnailCollectionItem
        )

        XCTAssertEqual(first.view.accessibilityLabel(), "Slide 1: Opening")
        XCTAssertEqual(second.view.accessibilityLabel(), "Slide 2: (Untitled)")
        XCTAssertEqual(
            accessibilityElements(in: first.view).map { $0.accessibilityLabel() },
            ["Slide 1: Opening"]
        )
        XCTAssertTrue(first.view.accessibilityPerformPress())
        XCTAssertEqual(activated, [0])
    }

    func testThumbnailOnlyAppliesToMatchingDeckVersionAndReuseClearsIt() throws {
        let sidebar = makeSidebar()
        sidebar.updateSlides(titles: ["Opening"], deckVersion: 5)
        let collectionView = try collectionView(in: sidebar)
        let staleImage = NSImage(size: NSSize(width: 320, height: 180))
        let currentImage = NSImage(size: NSSize(width: 320, height: 180))

        sidebar.setThumbnail(staleImage, at: 0, deckVersion: 4)
        var collectionItem = try item(
            at: 0,
            from: sidebar,
            collectionView: collectionView
        )
        XCTAssertNil(collectionItem.displayedImage)

        sidebar.setThumbnail(currentImage, at: 0, deckVersion: 5)
        collectionItem = try item(
            at: 0,
            from: sidebar,
            collectionView: collectionView
        )
        XCTAssertTrue(collectionItem.displayedImage === currentImage)

        sidebar.updateSlides(titles: ["Replacement"], deckVersion: 6)
        collectionItem.prepareForReuse()
        XCTAssertNil(collectionItem.displayedImage)
        let replacement = try item(
            at: 0,
            from: sidebar,
            collectionView: collectionView
        )
        XCTAssertNil(replacement.displayedImage)
    }

    func testDelegateSelectionCallsBackAndProgrammaticSelectionUpdatesState() throws {
        let sidebar = makeSidebar()
        sidebar.updateSlides(
            titles: ["Opening", "Architecture", "Questions"],
            deckVersion: 9
        )
        let collectionView = try collectionView(in: sidebar)
        var selectedIndexes: [Int] = []
        sidebar.onSelectIndex = { selectedIndexes.append($0) }

        sidebar.collectionView(
            collectionView,
            didSelectItemsAt: [IndexPath(item: 1, section: 0)]
        )

        XCTAssertEqual(selectedIndexes, [1])
        XCTAssertEqual(sidebar.currentSelection, 1)

        sidebar.select(index: 2, scrollToVisible: false)
        XCTAssertEqual(sidebar.currentSelection, 2)
        XCTAssertEqual(selectedIndexes, [1])
    }

    func testItemWidthTracksSidebarAndImageAreaRemainsSixteenByNine() throws {
        let sidebar = makeSidebar(width: 300)
        sidebar.updateSlides(titles: ["Opening"], deckVersion: 1)
        sidebar.layoutSubtreeIfNeeded()
        let collectionView = try collectionView(in: sidebar)
        let size = sidebar.collectionView(
            collectionView,
            layout: try XCTUnwrap(collectionView.collectionViewLayout),
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )
        let imageWidth = size.width
            - SlideThumbnailCollectionItem.horizontalInset * 2
        let imageHeight = size.height
            - SlideThumbnailCollectionItem.verticalChromeHeight

        XCTAssertEqual(imageWidth / imageHeight, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(size.width, sidebar.bounds.width)
    }

    private func makeSidebar(width: CGFloat = 280) -> SlideThumbnailSidebar {
        let sidebar = SlideThumbnailSidebar(
            frame: NSRect(x: 0, y: 0, width: width, height: 600)
        )
        sidebar.layoutSubtreeIfNeeded()
        return sidebar
    }

    private func collectionView(
        in view: NSView
    ) throws -> NSCollectionView {
        try XCTUnwrap(
            descendants(in: view).compactMap { $0 as? NSCollectionView }.first
        )
    }

    private func item(
        at index: Int,
        from sidebar: SlideThumbnailSidebar,
        collectionView: NSCollectionView
    ) throws -> SlideThumbnailCollectionItem {
        try XCTUnwrap(
            sidebar.collectionView(
                collectionView,
                itemForRepresentedObjectAt: IndexPath(item: index, section: 0)
            ) as? SlideThumbnailCollectionItem
        )
    }

    private func visibleLabels(in view: NSView) -> [String] {
        descendants(in: view)
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isHidden }
            .map(\.stringValue)
    }

    private func accessibilityElements(in view: NSView) -> [NSView] {
        descendants(in: view).filter { $0.isAccessibilityElement() }
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
