import Foundation
import XCTest
@testable import MarkdStage

final class PresentationServerTests: XCTestCase {
    func testStateDeckAndNavigationContract() async throws {
        let webRoot = try makeWebRoot()
        defer { try? FileManager.default.removeItem(at: webRoot.deletingLastPathComponent()) }

        let session = PresentationSession()
        let sourceURL = webRoot.deletingLastPathComponent().appendingPathComponent("deck.md")
        try "# First\n\n---\n\n# Second".write(to: sourceURL, atomically: true, encoding: .utf8)
        let document = MarkdownDeckParser().parse(try String(contentsOf: sourceURL, encoding: .utf8))
        _ = session.load(
            document,
            sourceURL: sourceURL,
            workspaceRoot: sourceURL.deletingLastPathComponent()
        )

        let server = try PresentationServer(session: session, webRoot: webRoot)
        try server.start()
        defer { server.stop() }
        let baseURL = try XCTUnwrap(server.baseURL)

        let (indexData, indexResponse) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("index.html")
        )
        XCTAssertEqual((indexResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: indexData, as: UTF8.self), "<!doctype html>")

        let (stateData, stateResponse) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("state")
        )
        XCTAssertEqual((stateResponse as? HTTPURLResponse)?.statusCode, 200)
        let state = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        )
        let requiredKeys: Set<String> = [
            "version", "deckVersion", "markdown", "index", "total", "theme",
            "themeLocked", "customThemeCss", "customThemeMeta", "mode",
            "sourceBacked", "sourceMode", "sourceWatchStatus", "sourceWatchError",
            "presenterRunning", "architectureEdit", "architectureDetailedEdit"
        ]
        XCTAssertTrue(requiredKeys.isSubset(of: Set(state.keys)))
        XCTAssertEqual(state["index"] as? Int, 0)
        XCTAssertEqual(state["total"] as? Int, 3)

        var navigation = URLRequest(url: baseURL.appendingPathComponent("navigate"))
        navigation.httpMethod = "POST"
        navigation.setValue("application/json", forHTTPHeaderField: "Content-Type")
        navigation.setValue(
            "http://127.0.0.1:\(try XCTUnwrap(baseURL.port))",
            forHTTPHeaderField: "Origin"
        )
        navigation.httpBody = try JSONSerialization.data(withJSONObject: ["delta": 1])
        let (navigationData, navigationResponse) = try await URLSession.shared.data(for: navigation)
        XCTAssertEqual((navigationResponse as? HTTPURLResponse)?.statusCode, 200)
        let result = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: navigationData) as? [String: Any]
        )
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["index"] as? Int, 1)
        XCTAssertEqual(session.currentSnapshot().index, 1)

        let (deckData, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("deck")
        )
        let deck = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: deckData) as? [String: Any]
        )
        XCTAssertEqual((deck["slides"] as? [String])?.count, 3)

        session.clear()
        let (clearedData, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("state")
        )
        let cleared = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: clearedData) as? [String: Any]
        )
        XCTAssertEqual(cleared["total"] as? Int, 0)
        XCTAssertEqual(cleared["sourceBacked"] as? Bool, false)
    }

    func testRejectsMissingToken() async throws {
        let webRoot = try makeWebRoot()
        defer { try? FileManager.default.removeItem(at: webRoot.deletingLastPathComponent()) }
        let server = try PresentationServer(session: PresentationSession(), webRoot: webRoot)
        try server.start()
        defer { server.stop() }
        let baseURL = try XCTUnwrap(server.baseURL)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/state"
        let (_, response) = try await URLSession.shared.data(from: try XCTUnwrap(components.url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    private func makeWebRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStageServerTests-\(UUID().uuidString)", isDirectory: true)
        let webRoot = root.appendingPathComponent("Web", isDirectory: true)
        try FileManager.default.createDirectory(
            at: webRoot.appendingPathComponent("renderer", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: webRoot.appendingPathComponent("vendor", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "<!doctype html>".write(
            to: webRoot.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
        return webRoot
    }
}
