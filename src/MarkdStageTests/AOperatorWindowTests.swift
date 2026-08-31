import AppKit
import PDFKit
import XCTest
@testable import MarkdStage

@MainActor
final class AOperatorWindowTests: XCTestCase {
    private static var retainedControllers: [PresentationWindowController] = []

    override nonisolated func setUp() {
        super.setUp()
        Self.clearLayoutDefaults()
    }

    override nonisolated func tearDown() {
        Self.clearLayoutDefaults()
        super.tearDown()
    }

    func testOperatorLayoutSelectionAndCloseShareOneWindow() async throws {
        let session = PresentationSession()
        let root = FileManager.default.temporaryDirectory
        _ = session.load(
            DeckDocument(
                slides: ["# One", "# Two", "# Three"],
                metadata: [:],
                theme: "dark",
                themeFile: ""
            ),
            sourceURL: root.appendingPathComponent("deck.md"),
            workspaceRoot: root
        )
        let server = try PresentationServer(session: session)
        try server.start()
        defer { server.stop() }

        let controller = PresentationWindowController(
            session: session,
            server: server,
            thumbnailProvider: NoopThumbnailProvider()
        )
        Self.retainedControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.layoutIfNeeded()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let allButtons = buttons(in: contentView)
        let sidebar = try XCTUnwrap(
            descendants(in: contentView).compactMap {
                $0 as? SlideThumbnailSidebar
            }.first
        )
        let splitViews = descendants(in: contentView).compactMap { $0 as? NSSplitView }
        let paneLabels = Set(labels(in: contentView))
        XCTAssertFalse(allButtons.contains(where: { $0.title == "Open" }))
        XCTAssertFalse(allButtons.contains(where: { $0.title == "Close" }))
        XCTAssertFalse(allButtons.contains(where: { $0.title == "Slide List" }))
        XCTAssertTrue(allButtons.contains(where: {
            $0.title == "Start Presentation" && $0.isEnabled
        }))
        XCTAssertTrue(allButtons.contains(where: {
            $0.title == "Export PDF" && $0.isEnabled
        }))
        XCTAssertEqual(splitViews.count, 3)
        XCTAssertEqual(splitViews.filter(\.isVertical).count, 2)
        XCTAssertEqual(splitViews.filter { !$0.isVertical }.count, 1)
        XCTAssertTrue(paneLabels.isSuperset(of: [
            "SLIDES",
            "CURRENT SLIDE",
            "SPEAKER NOTES",
            "NEXT SLIDE"
        ]))
        for splitView in splitViews {
            splitView.layoutSubtreeIfNeeded()
            let before = firstPaneThickness(in: splitView)
            let position = dividerPosition(in: splitView)
            splitView.setPosition(position + 20, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
            if abs(firstPaneThickness(in: splitView) - before) <= 0.5 {
                splitView.setPosition(position - 20, ofDividerAt: 0)
                splitView.layoutSubtreeIfNeeded()
            }
            XCTAssertNotEqual(
                firstPaneThickness(in: splitView),
                before,
                accuracy: 0.5
            )
        }
        XCTAssertEqual(sidebar.itemCount, 3)
        XCTAssertEqual(sidebar.currentSelection, 0)

        sidebar.onSelectIndex?(2)
        await Task.yield()

        XCTAssertEqual(session.currentSnapshot().index, 2)
        XCTAssertEqual(sidebar.currentSelection, 2)

        controller.closeDocument(nil)
        await Task.yield()

        XCTAssertEqual(session.currentSnapshot().total, 0)
        XCTAssertEqual(controller.window?.title, "MarkdStage")
        XCTAssertNotNil(controller.window)
        XCTAssertTrue(allButtons.contains(where: {
            $0.title == "Open Markdown…" && $0.isEnabled
        }))
        for title in ["Start Presentation", "Export PDF"] {
            XCTAssertTrue(allButtons.contains(where: {
                $0.title == title && !$0.isEnabled
            }))
        }
        XCTAssertTrue(labels(in: contentView).contains("No Markdown file open"))
        XCTAssertTrue(descendants(in: contentView).contains(where: {
            ($0 as? EmptyStateView)?.isHidden == false
        }))
        XCTAssertEqual(sidebar.itemCount, 0)
    }

    func testMenusRetainFileCommandsAndOmitLegacySlideList() throws {
        let menu = MainMenuBuilder.make(delegate: AppDelegate())
        let fileMenu = try XCTUnwrap(menu.items.first(where: { $0.title == "File" })?.submenu)
        let fileTitles = Set(fileMenu.items.map(\.title))
        XCTAssertTrue(fileTitles.contains("Open…"))
        XCTAssertTrue(fileTitles.contains("Close Markdown"))

        let presentationMenu = try XCTUnwrap(
            menu.items.first(where: { $0.title == "Presentation" })?.submenu
        )
        XCTAssertFalse(presentationMenu.items.contains(where: {
            $0.title == "Slide List…" || $0.keyEquivalent.lowercased() == "l"
        }))
    }

    @MainActor
    private final class NoopThumbnailProvider: SlideThumbnailProviding {
        func render(
            deckVersion: Int64,
            slideCount: Int,
            onThumbnail: @escaping (Int64, Int, NSImage) -> Void,
            completion: @escaping (Int64, Result<Void, Error>) -> Void
        ) {
            completion(deckVersion, .success(()))
        }

        func cancel() {}

        func shutdown() {}

        func cachedDocument(deckVersion: Int64) -> PDFDocument? {
            nil
        }
    }

    private func buttons(in view: NSView) -> [NSButton] {
        let own = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap(buttons)
    }

    private func labels(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap(labels)
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func firstPaneThickness(in splitView: NSSplitView) -> CGFloat {
        guard let first = splitView.arrangedSubviews.first else { return 0 }
        return splitView.isVertical ? first.frame.width : first.frame.height
    }

    private func dividerPosition(in splitView: NSSplitView) -> CGFloat {
        guard splitView.arrangedSubviews.count >= 2 else { return 0 }
        let first = splitView.arrangedSubviews[0].frame
        let second = splitView.arrangedSubviews[1].frame
        if splitView.isVertical {
            return first.maxX
        }
        return first.midY < second.midY ? first.maxY : first.minY
    }

    private nonisolated static func clearLayoutDefaults() {
        for key in [
            "NSSplitView Subview Frames MarkdStageOperatorOuterSplitV2",
            "NSSplitView Subview Frames MarkdStageOperatorWorkspaceSplitV2",
            "NSSplitView Subview Frames MarkdStageOperatorLowerSplitV2"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
