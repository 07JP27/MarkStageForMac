import AppKit
import XCTest
@testable import MarkdStage

@MainActor
final class PresentationWindowControllerTests: XCTestCase {
    func testCloseActionClearsLoadedDeckWithoutClosingWindow() async throws {
        let session = PresentationSession()
        let root = FileManager.default.temporaryDirectory
        _ = session.load(
            DeckDocument(slides: ["# Slide"], metadata: [:], theme: "dark", themeFile: ""),
            sourceURL: root.appendingPathComponent("deck.md"),
            workspaceRoot: root
        )
        let server = try PresentationServer(session: session)
        try server.start()
        defer { server.stop() }

        let controller = PresentationWindowController(session: session, server: server)
        defer { controller.close() }

        controller.closeDocument(nil)
        await Task.yield()

        XCTAssertEqual(session.currentSnapshot().total, 0)
        XCTAssertEqual(controller.window?.title, "MarkdStage")
        XCTAssertNotNil(controller.window)
    }

    func testHeaderOmitsFileButtonsAndEmptyStateKeepsNativeOpenAction() throws {
        let session = PresentationSession()
        let server = try PresentationServer(session: session)
        try server.start()
        defer { server.stop() }
        let controller = PresentationWindowController(session: session, server: server)
        defer { controller.close() }
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let allButtons = buttons(in: contentView)

        XCTAssertFalse(allButtons.contains(where: { $0.title == "Open" }))
        XCTAssertFalse(allButtons.contains(where: { $0.title == "Close" }))
        XCTAssertTrue(allButtons.contains(where: {
            $0.title == "Open Markdown…" && $0.isEnabled
        }))
        for title in ["Slide List", "Start Presentation", "Export PDF"] {
            XCTAssertTrue(allButtons.contains(where: {
                $0.title == title && !$0.isEnabled
            }))
        }
        XCTAssertTrue(labels(in: contentView).contains("No Markdown file open"))
        XCTAssertTrue(descendants(in: contentView).contains(where: {
            $0 is EmptyStateView
        }))
    }

    func testFileMenuRetainsOpenAndCloseCommands() throws {
        let menu = MainMenuBuilder.make(delegate: AppDelegate())
        let fileMenu = try XCTUnwrap(menu.items.first(where: { $0.title == "File" })?.submenu)
        let titles = Set(fileMenu.items.map(\.title))

        XCTAssertTrue(titles.contains("Open…"))
        XCTAssertTrue(titles.contains("Close Markdown"))
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
}
