import AppKit
import XCTest
@testable import MarkdStage

@MainActor
final class PresentationWindowControllerTests: XCTestCase {
    func testCloseButtonClearsLoadedDeckWithoutClosingWindow() async throws {
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
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let closeButton = try XCTUnwrap(
            buttons(in: contentView).first(where: { $0.title == "Close" })
        )
        XCTAssertTrue(closeButton.isEnabled)

        closeButton.performClick(nil)
        await Task.yield()

        XCTAssertEqual(session.currentSnapshot().total, 0)
        XCTAssertEqual(controller.window?.title, "MarkdStage")
        XCTAssertFalse(closeButton.isEnabled)
        XCTAssertNotNil(controller.window)
    }

    private func buttons(in view: NSView) -> [NSButton] {
        let own = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap(buttons)
    }
}
