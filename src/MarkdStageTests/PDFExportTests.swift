import AppKit
import PDFKit
import XCTest
@testable import MarkdStage

@MainActor
final class PDFExportTests: XCTestCase {
    func testExportProducesReadablePDF() async throws {
        let session = PresentationSession()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStagePDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("deck.md")
        let markdown = """
        # PDF export

        ---

        ## Mermaid diagram

        ```mermaid
        flowchart LR
            Markdown --> Stage
        ```
        """
        try markdown.write(to: sourceURL, atomically: true, encoding: .utf8)
        let document = MarkdownDeckParser().parse(markdown)
        _ = session.load(document, sourceURL: sourceURL, workspaceRoot: root)

        let server = try PresentationServer(session: session)
        try server.start()
        defer { server.stop() }
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parentWindow.orderBack(nil)
        defer { parentWindow.close() }

        let outputURL = root.appendingPathComponent("deck.pdf")
        let completed = expectation(description: "PDF export completed")
        var lastStatus = ""
        let coordinator = PDFExportCoordinator(
            parentWindow: parentWindow,
            baseURL: try XCTUnwrap(server.baseURL),
            onCompletion: { completed.fulfill() },
            onStatus: {
                lastStatus = $0
                print("PDF status: \($0)")
            }
        )
        coordinator.export(to: outputURL)
        await fulfillment(of: [completed], timeout: 20)

        let data = try Data(contentsOf: outputURL)
        XCTAssertFalse(lastStatus.contains("timed out"), lastStatus)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, document.slides.count)
        XCTAssertTrue(pdf.string?.contains("PDF export") == true)
    }
}
