import AppKit
import PDFKit
import XCTest
@testable import MarkdStage

@MainActor
final class ZPDFExportTests: XCTestCase {
    func testCoordinatorWritesReadableMultipagePDF() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let preparedDocument = try makePreparedPDF(
            pageCount: fixture.document.slides.count
        )

        let outputURL = fixture.root.appendingPathComponent("deck.pdf")
        let exportCompleted = expectation(description: "PDF export completed")
        var lastStatus = ""
        let coordinator = PDFExportCoordinator(
            parentWindow: fixture.parentWindow,
            baseURL: fixture.baseURL,
            preparedDocument: preparedDocument,
            onCompletion: { exportCompleted.fulfill() },
            onStatus: {
                lastStatus = $0
                print("PDF status: \($0)")
            }
        )
        coordinator.export(to: outputURL)
        await fulfillment(of: [exportCompleted], timeout: 20)

        let exportedData = try Data(contentsOf: outputURL)
        XCTAssertFalse(lastStatus.contains("timed out"), lastStatus)
        XCTAssertTrue(exportedData.starts(with: Data("%PDF".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(data: exportedData))
        XCTAssertEqual(pdf.pageCount, fixture.document.slides.count)
    }

    private func makeFixture() throws -> Fixture {
        let session = PresentationSession()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStagePDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("deck.md")
        let markdown = """
        # PDF export

        ---
        page: diagram
        ---

        ## Mermaid diagram

        ```mermaid
        flowchart LR
            Markdown --> Stage
        ```

        ---
        page: diagram
        ---

        ## Mermaid diagram
        """
        try markdown.write(to: sourceURL, atomically: true, encoding: .utf8)
        let document = MarkdownDeckParser().parse(markdown)
        _ = session.load(document, sourceURL: sourceURL, workspaceRoot: root)

        let server = try PresentationServer(session: session)
        try server.start()
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parentWindow.orderBack(nil)
        return Fixture(
            root: root,
            document: document,
            server: server,
            baseURL: try XCTUnwrap(server.baseURL),
            parentWindow: parentWindow
        )
    }

    private func makePreparedPDF(pageCount: Int) throws -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 1_280, height: 720))
            image.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSString(string: index == 0 ? "PDF export" : "Slide \(index + 1)").draw(
                at: NSPoint(x: 80, y: 80),
                withAttributes: [.font: NSFont.systemFont(ofSize: 32)]
            )
            image.unlockFocus()
            document.insert(try XCTUnwrap(PDFPage(image: image)), at: index)
        }
        return document
    }

    private struct Fixture {
        let root: URL
        let document: DeckDocument
        let server: PresentationServer
        let baseURL: URL
        let parentWindow: NSWindow

        @MainActor
        func cleanUp() {
            server.stop()
            parentWindow.close()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
