import XCTest
@testable import MarkdStage

final class CoreTests: XCTestCase {
    func testParserInheritsMetadataAndAddsNumberingAndBackCover() {
        let document = MarkdownDeckParser().parse(
            """
            ---
            deck: Demo
            layout: title
            theme: microsoft
            ---
            # Cover

            ---

            ## Details

            - One
            """
        )

        XCTAssertEqual(document.slides.count, 3)
        XCTAssertTrue(document.slides[0].contains("layout: title"))
        XCTAssertFalse(document.slides[0].contains("page:"))
        XCTAssertTrue(document.slides[1].contains("page: 2"))
        XCTAssertTrue(document.slides[1].contains("total: 2"))
        XCTAssertTrue(document.slides[2].contains("layout: backcover"))
        XCTAssertEqual(document.theme, "microsoft")
    }

    func testParserDoesNotSplitInsideFenceOrSetextHeading() {
        let document = MarkdownDeckParser().parse(
            """
            ## Code

            ```text
            ---
            ```

            Heading
            ---

            Text
            """
        )
        XCTAssertEqual(document.slides.count, 2)
        XCTAssertTrue(document.slides[0].contains("```text\n---\n```"))
        XCTAssertTrue(document.slides[0].contains("Heading\n---"))
    }

    func testParserMatchesSharedCorpus() throws {
        struct Entry: Decodable {
            let name: String
            let markdown: String
            let slides: [String]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "markdown-deck-corpus",
            withExtension: "json"
        ))
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        for entry in entries {
            XCTAssertEqual(
                MarkdownDeckParser().parse(entry.markdown, addBackCover: false).slides,
                entry.slides,
                entry.name
            )
        }
    }

    func testSpeakerNotesAndRemoval() {
        let markdown = """
        ## Slide

        <!--
        Start with **why**.
        Then show the demo.
        -->

        ```html
        <!-- visible example -->
        ```
        """
        XCTAssertEqual(
            SpeakerNotesExtractor.extract(markdown),
            "Start with **why**.\nThen show the demo."
        )
        XCTAssertTrue(
            SpeakerNotesExtractor.remove(from: markdown).contains("<!-- visible example -->")
        )
    }

    func testSpeakerNotesIgnoreDirectiveAndIndentedMarkers() {
        let markdown = """
        <!-- slide-size: large -->
        `<!-- inline code -->`
            <!-- indented code -->
        <!-- actual note -->
        """
        XCTAssertEqual(SpeakerNotesExtractor.extract(markdown), "actual note")
    }

    func testSlideTitleDeriver() {
        XCTAssertEqual(
            SlideTitleDeriver.derive("Intro\n\n## Selected heading\n# Later"),
            "Selected heading"
        )
        XCTAssertEqual(
            SlideTitleDeriver.derive("<!-- note -->\nPublic body line"),
            "Public body line"
        )
        XCTAssertEqual(
            SlideTitleDeriver.derive(
                "### > **[`Linked_title`](https://example.com)** and ![image](asset.png) ~tag~"
            ),
            "Linkedtitle and image tag"
        )
        XCTAssertEqual(
            SlideTitleDeriver.derive("# Markdown,<br>ready for the **stage**."),
            "Markdown, ready for the stage."
        )
        XCTAssertEqual(
            SlideTitleDeriver.derive(
                """
                ``` swift linenums
                # Not the slide title
                ```
                ## Real <em>title</em> &amp; details
                """
            ),
            "Real title & details"
        )
        XCTAssertEqual(
            SlideTitleDeriver.derive("<p>Plain <strong>body</strong><br />line</p>"),
            "Plain body line"
        )
    }

    func testSessionPreservesPositionAndClampsNavigation() {
        let session = PresentationSession()
        let root = URL(fileURLWithPath: "/tmp")
        _ = session.load(
            DeckDocument(slides: ["a", "b", "c"], metadata: [:], theme: "dark", themeFile: ""),
            sourceURL: root.appendingPathComponent("a.md"),
            workspaceRoot: root
        )
        XCTAssertFalse(session.navigate(by: -1))
        XCTAssertTrue(session.navigate(to: 2))
        let snapshot = session.load(
            DeckDocument(slides: ["x", "y"], metadata: [:], theme: "light", themeFile: ""),
            sourceURL: root.appendingPathComponent("a.md"),
            workspaceRoot: root
        )
        XCTAssertEqual(snapshot.index, 1)
        XCTAssertEqual(snapshot.currentMarkdown, "y")
        XCTAssertEqual(snapshot.deckVersion, 2)
    }

    func testSessionDeltaNavigationHandlesIntegerBounds() {
        let session = PresentationSession()
        let root = URL(fileURLWithPath: "/tmp")
        _ = session.load(
            DeckDocument(slides: ["a", "b", "c"], metadata: [:], theme: "dark", themeFile: ""),
            sourceURL: root.appendingPathComponent("a.md"),
            workspaceRoot: root
        )

        XCTAssertTrue(session.navigate(by: Int.max))
        XCTAssertEqual(session.currentSnapshot().index, 2)
        XCTAssertTrue(session.navigate(by: Int.min))
        XCTAssertEqual(session.currentSnapshot().index, 0)
    }

    func testSessionDeliversConcurrentNotificationsInVersionOrder() {
        let session = PresentationSession()
        let root = URL(fileURLWithPath: "/tmp")
        let terminalNotification = expectation(description: "Terminal snapshot delivered")
        let recorder = SnapshotVersionRecorder(terminalExpectation: terminalNotification)
        let observerID = session.addObserver { snapshot in
            recorder.append(snapshot)
        }
        defer { session.removeObserver(observerID) }

        _ = session.load(
            DeckDocument(
                slides: (0..<20).map(String.init),
                metadata: [:],
                theme: "dark",
                themeFile: ""
            ),
            sourceURL: root.appendingPathComponent("a.md"),
            workspaceRoot: root
        )
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            _ = session.navigate(to: index % 20)
        }
        let terminal = session.clear()

        wait(for: [terminalNotification], timeout: 2)
        let versions = recorder.values()
        XCTAssertEqual(versions, versions.sorted())
        XCTAssertEqual(Set(versions).count, versions.count)
        XCTAssertEqual(versions.last, terminal.version)
    }

    func testSessionClearRemovesDeckAndSourceState() {
        let session = PresentationSession()
        let root = URL(fileURLWithPath: "/tmp")
        let loaded = session.load(
            DeckDocument(slides: ["a", "b"], metadata: [:], theme: "light", themeFile: ""),
            sourceURL: root.appendingPathComponent("deck.md"),
            workspaceRoot: root
        )

        let cleared = session.clear()

        XCTAssertTrue(cleared.slides.isEmpty)
        XCTAssertEqual(cleared.index, 0)
        XCTAssertNil(cleared.sourceURL)
        XCTAssertNil(cleared.workspaceRoot)
        XCTAssertEqual(cleared.theme.name, "dark")
        XCTAssertEqual(cleared.version, loaded.version + 1)
        XCTAssertEqual(cleared.deckVersion, loaded.deckVersion + 1)
    }

    func testPathSecurityRejectsTraversalAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStagePathTests-\(UUID().uuidString)", isDirectory: true)
        let allowed = root.appendingPathComponent("allowed", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "safe".write(
            to: allowed.appendingPathComponent("safe.svg"),
            atomically: true,
            encoding: .utf8
        )
        try "secret".write(
            to: outside.appendingPathComponent("secret.svg"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: allowed.appendingPathComponent("escape.svg"),
            withDestinationURL: outside.appendingPathComponent("secret.svg")
        )

        XCTAssertNotNil(PathSecurity.resolveFile(in: allowed, relativePath: "safe.svg"))
        XCTAssertNil(PathSecurity.resolveFile(in: allowed, relativePath: "../outside/secret.svg"))
        XCTAssertNil(PathSecurity.resolveFile(in: allowed, relativePath: "%2e%2e/outside/secret.svg"))
        XCTAssertNil(PathSecurity.resolveFile(in: allowed, relativePath: "/etc/passwd"))
        XCTAssertNil(PathSecurity.resolveFile(in: allowed, relativePath: "escape.svg"))
    }

    func testThemeServiceAcceptsVariablesAndRejectsUnsafeCSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStageThemeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("deck.md")
        try "# Deck".write(to: sourceURL, atomically: true, encoding: .utf8)
        let themeURL = root.appendingPathComponent("theme.css")
        let document = DeckDocument(
            slides: ["# Deck"],
            metadata: [:],
            theme: "custom",
            themeFile: "theme.css"
        )

        try ":root { --accent: #ffb547; --surface: rgb(11, 16, 32); }".write(
            to: themeURL,
            atomically: true,
            encoding: .utf8
        )
        let theme = try ThemeService().load(
            document: document,
            sourceURL: sourceURL,
            workspaceRoot: root
        )
        XCTAssertEqual(theme.name, "custom")
        XCTAssertTrue(theme.css.contains("--accent:#ffb547;"))

        for unsafeValue in [
            "url(https://example.com/a.png)",
            "@import 'theme.css'",
            "javascript:alert(1)",
            "expression(alert(1))",
            "</style><script>alert(1)</script>",
            "red} body { display: none",
            "red { color: transparent"
        ] {
            try ":root { --unsafe: \(unsafeValue); }".write(
                to: themeURL,
                atomically: true,
                encoding: .utf8
            )
            XCTAssertThrowsError(
                try ThemeService().load(
                    document: document,
                    sourceURL: sourceURL,
                    workspaceRoot: root
                ),
                unsafeValue
            )
        }
    }

    func testRequiredResourcesAreBundled() throws {
        let bundle = Bundle(for: PresentationServer.self)
        XCTAssertNotNil(bundle.url(forResource: "Web", withExtension: nil))
        XCTAssertNotNil(bundle.url(forResource: "LICENSE", withExtension: nil))
        XCTAssertNotNil(bundle.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md"))
        XCTAssertNotNil(bundle.url(
            forResource: "MarkdStage-MIT",
            withExtension: "txt",
            subdirectory: "LICENSES"
        ))
        for license in ["marked", "purify", "highlight", "mermaid"] {
            XCTAssertNotNil(
                bundle.url(
                    forResource: license,
                    withExtension: "LICENSE",
                    subdirectory: "Web/vendor"
                ),
                "\(license).LICENSE"
            )
        }
        let mermaidURL = try XCTUnwrap(bundle.url(
            forResource: "mermaid.min",
            withExtension: "js",
            subdirectory: "Web/vendor"
        ))
        let mermaid = try String(contentsOf: mermaidURL, encoding: .utf8)
        XCTAssertTrue(mermaid.contains(#"version:"11.16.1""#))
    }
}

private final class SnapshotVersionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let terminalExpectation: XCTestExpectation
    private var recorded: [Int64] = []

    init(terminalExpectation: XCTestExpectation) {
        self.terminalExpectation = terminalExpectation
    }

    func append(_ snapshot: PresentationSnapshot) {
        lock.withLock {
            recorded.append(snapshot.version)
            if snapshot.slides.isEmpty, snapshot.version > 1 {
                terminalExpectation.fulfill()
            }
        }
    }

    func values() -> [Int64] {
        lock.withLock { recorded }
    }
}
