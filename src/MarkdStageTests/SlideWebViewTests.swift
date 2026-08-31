import AppKit
import XCTest

@testable import MarkdStage

@MainActor
final class SlideWebViewTests: XCTestCase {
    func testCanonicalViewportIsAspectFitWithoutResizingWebView() {
        let slideView = SlideWebView(
            allowedOrigin: URL(string: "http://127.0.0.1:8080/")!
        )

        slideView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        slideView.layoutSubtreeIfNeeded()

        XCTAssertEqual(slideView.webView.frame.size, SlideWebView.canonicalSize)
        XCTAssertEqual(slideView.canonicalCanvasFrame.width, 1_000, accuracy: 0.001)
        XCTAssertEqual(slideView.canonicalCanvasFrame.height, 562.5, accuracy: 0.001)
        XCTAssertEqual(slideView.canonicalCanvasFrame.minY, 68.75, accuracy: 0.001)

        slideView.frame.size = NSSize(width: 640, height: 640)
        slideView.layoutSubtreeIfNeeded()

        XCTAssertEqual(slideView.webView.frame.size, SlideWebView.canonicalSize)
        XCTAssertEqual(slideView.canonicalCanvasFrame.width, 640, accuracy: 0.001)
        XCTAssertEqual(slideView.canonicalCanvasFrame.height, 360, accuracy: 0.001)
        XCTAssertEqual(slideView.canonicalCanvasFrame.minY, 140, accuracy: 0.001)
    }
}
