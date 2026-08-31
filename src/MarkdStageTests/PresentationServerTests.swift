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
        let document = MarkdownDeckParser().parse(
            try String(contentsOf: sourceURL, encoding: .utf8))
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
            "presenterRunning", "architectureEdit", "architectureDetailedEdit",
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

    func testExportAssetsRemainBoundToTheStartingSnapshot() async throws {
        let webRoot = try makeWebRoot()
        let root = webRoot.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeAssetDeck(named: "first", contents: "deck-a", in: root)
        let second = try makeAssetDeck(named: "second", contents: "deck-b", in: root)
        let session = PresentationSession()
        _ = session.load(
            DeckDocument(slides: ["# First"], metadata: [:], theme: "custom", themeFile: ""),
            sourceURL: first.sourceURL,
            workspaceRoot: first.workspaceRoot,
            theme: ThemeState(name: "custom", assetRoot: first.themeRoot)
        )

        let server = try PresentationServer(session: session, webRoot: webRoot)
        try server.start()
        defer { server.stop() }
        let baseURL = try XCTUnwrap(server.baseURL)
        let exportToken = UUID().uuidString
        let (_, exportResponse) = try await URLSession.shared.data(
            from: try URL(
                baseURL: baseURL,
                path: "export-data",
                query: ["token": exportToken]
            )
        )
        XCTAssertEqual((exportResponse as? HTTPURLResponse)?.statusCode, 200)
        var keepAlive = URLRequest(
            url: try URL(
                baseURL: baseURL,
                path: "export-status",
                query: ["token": exportToken]
            )
        )
        keepAlive.httpMethod = "POST"
        let (_, keepAliveResponse) = try await URLSession.shared.data(for: keepAlive)
        XCTAssertEqual((keepAliveResponse as? HTTPURLResponse)?.statusCode, 200)

        _ = session.load(
            DeckDocument(slides: ["# Second"], metadata: [:], theme: "custom", themeFile: ""),
            sourceURL: second.sourceURL,
            workspaceRoot: second.workspaceRoot,
            theme: ThemeState(name: "custom", assetRoot: second.themeRoot)
        )

        let (exportDeckAsset, _) = try await URLSession.shared.data(
            from: try URL(
                baseURL: baseURL,
                path: "assets/shared.svg",
                query: ["exportToken": exportToken]
            )
        )
        let (currentDeckAsset, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("assets/shared.svg")
        )
        let (exportThemeAsset, _) = try await URLSession.shared.data(
            from: try URL(
                baseURL: baseURL,
                path: "theme-assets/logo.svg",
                query: ["exportToken": exportToken]
            )
        )
        let (currentThemeAsset, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("theme-assets/logo.svg")
        )

        XCTAssertEqual(String(decoding: exportDeckAsset, as: UTF8.self), "deck-a")
        XCTAssertEqual(String(decoding: currentDeckAsset, as: UTF8.self), "deck-b")
        XCTAssertEqual(String(decoding: exportThemeAsset, as: UTF8.self), "theme-first")
        XCTAssertEqual(String(decoding: currentThemeAsset, as: UTF8.self), "theme-second")
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

    private func makeAssetDeck(
        named name: String,
        contents: String,
        in root: URL
    ) throws -> (sourceURL: URL, workspaceRoot: URL, themeRoot: URL) {
        let workspaceRoot = root.appendingPathComponent(name, isDirectory: true)
        let assets = workspaceRoot.appendingPathComponent("assets", isDirectory: true)
        let themeRoot = workspaceRoot.appendingPathComponent("theme", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: themeRoot,
            withIntermediateDirectories: true
        )
        try contents.write(
            to: assets.appendingPathComponent("shared.svg"),
            atomically: true,
            encoding: .utf8
        )
        try "theme-\(name)".write(
            to: themeRoot.appendingPathComponent("logo.svg"),
            atomically: true,
            encoding: .utf8
        )
        let sourceURL = workspaceRoot.appendingPathComponent("deck.md")
        try "# \(name)".write(to: sourceURL, atomically: true, encoding: .utf8)
        return (sourceURL, workspaceRoot, themeRoot)
    }
}

extension URL {
    fileprivate init(baseURL: URL, path: String, query: [String: String]) throws {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )
        else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        components.queryItems = query.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        self = url
    }
}
