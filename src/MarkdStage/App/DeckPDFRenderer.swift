import AppKit
import PDFKit
import WebKit

@MainActor
final class DeckPDFRenderer: NSObject, WKNavigationDelegate {
    private static let stepTimeoutSeconds: TimeInterval = 30

    enum RenderError: LocalizedError, Equatable {
        case alreadyRendering
        case invalidRenderURL
        case loadFailed(String)
        case timedOut(String)
        case invalidRenderState
        case pageCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRendering:
                "PDF rendering is already in progress."
            case .invalidRenderURL:
                "PDF renderer URL could not be created."
            case .loadFailed(let details):
                "PDF renderer failed to load: \(details)"
            case .timedOut(let details):
                "PDF rendering timed out. \(details)"
            case .invalidRenderState:
                "The PDF renderer did not provide a valid canonical slide state."
            case .pageCreationFailed(let details):
                "Could not save the PDF: \(details)"
            }
        }
    }

    private let baseURL: URL
    private let onDiagnostics: (@MainActor (Int, String) -> Void)?
    private var webView: WKWebView?
    private var renderWindow: NSWindow?
    private var activeNavigation: WKNavigation?
    private var activeRenderID: UUID?
    private var stepTimeout: DispatchWorkItem?
    private var stepTimeoutGeneration: UUID?
    private var completion: (@MainActor (Result<PDFDocument, Error>) -> Void)?
    private var activeRetain: DeckPDFRenderer?

    init(
        parentWindow _: NSWindow?,
        baseURL: URL,
        onDiagnostics: (@MainActor (Int, String) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.onDiagnostics = onDiagnostics
    }

    func render(
        completion: @escaping @MainActor (Result<PDFDocument, Error>) -> Void
    ) {
        guard self.completion == nil else {
            completion(.failure(RenderError.alreadyRendering))
            return
        }

        let renderID = UUID()
        activeRenderID = renderID
        self.completion = completion
        activeRetain = self

        guard
            var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            complete(.failure(RenderError.invalidRenderURL), renderID: renderID)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "print", value: "1"),
            URLQueryItem(name: "token", value: renderID.uuidString),
        ]
        guard let renderURL = components.url else {
            complete(.failure(RenderError.invalidRenderURL), renderID: renderID)
            return
        }

        startRendering(renderURL, renderID: renderID)
    }

    private func startRendering(_ renderURL: URL, renderID: UUID) {
        guard activeRenderID == renderID, completion != nil else { return }
        let webView: WKWebView
        if let existing = self.webView {
            webView = existing
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(
                frame: NSRect(x: 0, y: 0, width: 1280, height: 720),
                configuration: configuration
            )
            webView.navigationDelegate = self
            webView.isInspectable = false

            let window = NSWindow(
                contentRect: NSRect(
                    x: -100_000,
                    y: -100_000,
                    width: 1280,
                    height: 720
                ),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.alphaValue = 1
            window.ignoresMouseEvents = true
            window.contentView = webView
            window.orderBack(nil)

            self.webView = webView
            renderWindow = window
        }
        activeNavigation = webView.load(
            URLRequest(url: renderURL, cachePolicy: .reloadIgnoringLocalCacheData)
        )
    }

    func cancel() {
        guard let activeRenderID else { return }
        complete(.failure(CancellationError()), renderID: activeRenderID)
    }

    func shutdown() {
        if let activeRenderID {
            complete(.failure(CancellationError()), renderID: activeRenderID)
        }
        cleanup()
        activeRetain = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation,
            let renderID = activeRenderID,
            isActive(renderID, in: webView)
        else {
            return
        }
        waitUntilReady(attempt: 0, renderID: renderID)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        failToLoad(
            error,
            navigation: navigation,
            renderID: activeRenderID,
            in: webView
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failToLoad(
            error,
            navigation: navigation,
            renderID: activeRenderID,
            in: webView
        )
    }

    private func failToLoad(
        _ error: Error,
        navigation: WKNavigation?,
        renderID: UUID?,
        in webView: WKWebView
    ) {
        guard navigation === activeNavigation,
            let renderID,
            isActive(renderID, in: webView)
        else {
            return
        }
        complete(
            .failure(RenderError.loadFailed(error.localizedDescription)),
            renderID: renderID
        )
    }

    private func waitUntilReady(
        attempt: Int,
        renderID: UUID
    ) {
        guard let webView, isActive(renderID, in: webView) else { return }
        guard attempt < 150 else {
            diagnoseTimeout(renderID: renderID)
            return
        }
        webView.evaluateJavaScript(
            """
            JSON.stringify({
              ready: Boolean(window.__presentationPrintReady),
              error: window.__presentationPrintState?.error || ""
            })
            """
        ) { [weak self] result, error in
            guard let self,
                let webView = self.webView,
                self.isActive(renderID, in: webView)
            else {
                return
            }
            if error == nil,
                let stateJSON = result as? String,
                let data = stateJSON.data(using: .utf8),
                let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                if let details = state["error"] as? String, !details.isEmpty {
                    self.complete(
                        .failure(RenderError.pageCreationFailed(details)),
                        renderID: renderID
                    )
                    return
                }
                if state["ready"] as? Bool == true {
                    self.beginPDFCapture(renderID: renderID)
                    return
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitUntilReady(
                    attempt: attempt + 1,
                    renderID: renderID
                )
            }
        }
    }

    private func diagnoseTimeout(renderID: UUID) {
        guard let webView, isActive(renderID, in: webView) else { return }
        let script = """
            JSON.stringify({
              ready: Boolean(window.__presentationPrintReady),
              printError: document.documentElement.getAttribute("data-print-error"),
              moduleLoaded: typeof window.marked !== "undefined",
              bodyClass: document.body?.className || "",
              title: document.title || "",
              fontsStatus: document.fonts?.status || "",
              slideCount: document.querySelectorAll("#stage > .deck").length,
              printState: window.__presentationPrintState || null,
              imageCount: document.querySelectorAll("#stage img, #stage image").length,
              mermaidCount: document.querySelectorAll("#stage .mermaid").length
            })
            """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self,
                let webView = self.webView,
                self.isActive(renderID, in: webView)
            else {
                return
            }
            let details = result as? String ?? "page state unavailable"
            self.complete(
                .failure(RenderError.timedOut(details)),
                renderID: renderID
            )
        }
    }

    private func beginPDFCapture(renderID: UUID) {
        guard let webView, isActive(renderID, in: webView) else { return }
        webView.evaluateJavaScript("window.__presentationPrintState") { [weak self] result, error in
            guard let self,
                let webView = self.webView,
                self.isActive(renderID, in: webView)
            else {
                return
            }
            guard error == nil,
                let state = result as? [String: Any],
                state["ready"] as? Bool == true,
                let slideCount = state["slideCount"] as? Int,
                slideCount > 0
            else {
                self.complete(
                    .failure(RenderError.invalidRenderState),
                    renderID: renderID
                )
                return
            }
            self.createPDFPage(
                slideCount: slideCount,
                index: 0,
                output: PDFDocument(),
                renderID: renderID
            )
        }
    }

    private func renderPrintSlide(
        at index: Int,
        renderID: UUID,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let webView, isActive(renderID, in: webView) else { return }
        scheduleStepTimeout(
            "The renderer did not finish slide \(index + 1).",
            renderID: renderID
        )
        webView.callAsyncJavaScript(
            "return await window.__presentationRenderPrintSlide(index);",
            arguments: ["index": index],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                    let webView = self.webView,
                    self.isActive(renderID, in: webView)
                else {
                    return
                }
                self.cancelStepTimeout()
                do {
                    let response = try result.get() as? [String: Any]
                    guard let response,
                        response["ok"] as? Bool == true,
                        response["ready"] as? Bool == true,
                        response["index"] as? Int == index
                    else {
                        let details =
                            response?["error"] as? String
                            ?? "The renderer did not confirm the requested slide."
                        throw RenderError.pageCreationFailed(details)
                    }
                    completion()
                } catch let error as RenderError {
                    self.complete(.failure(error), renderID: renderID)
                } catch {
                    self.complete(
                        .failure(
                            RenderError.pageCreationFailed(
                                error.localizedDescription
                            )
                        ),
                        renderID: renderID
                    )
                }
            }
        }
    }

    private func finishDocument(
        _ output: PDFDocument,
        expectedPageCount: Int,
        renderID: UUID
    ) {
        guard output.pageCount == expectedPageCount else {
            complete(
                .failure(
                    RenderError.pageCreationFailed(
                        "WebKit returned the wrong number of PDF pages."
                    )
                ),
                renderID: renderID
            )
            return
        }
        guard let data = output.dataRepresentation(),
            let detachedDocument = PDFDocument(data: data)
        else {
            complete(
                .failure(
                    RenderError.pageCreationFailed(
                        "WebKit returned an empty PDF."
                    )
                ),
                renderID: renderID
            )
            return
        }
        complete(.success(detachedDocument), renderID: renderID)
    }

    private func createPDFPage(
        slideCount: Int,
        index: Int,
        output: PDFDocument,
        renderID: UUID
    ) {
        guard let webView, isActive(renderID, in: webView) else { return }
        guard index < slideCount else {
            finishDocument(
                output,
                expectedPageCount: slideCount,
                renderID: renderID
            )
            return
        }

        webView.evaluateJavaScript(
            "JSON.stringify(window.__presentationPrintState?.diagnostics || null)"
        ) { [weak self] value, inspectionError in
            guard let self,
                let webView = self.webView,
                self.isActive(renderID, in: webView)
            else {
                return
            }
            guard inspectionError == nil,
                let diagnostics = value as? String,
                diagnostics != "null"
            else {
                self.complete(
                    .failure(RenderError.invalidRenderState),
                    renderID: renderID
                )
                return
            }
            self.capturePDFPage(
                slideCount: slideCount,
                index: index,
                output: output,
                diagnostics: diagnostics,
                renderID: renderID
            )
        }
    }

    private func capturePDFPage(
        slideCount: Int,
        index: Int,
        output: PDFDocument,
        diagnostics: String,
        renderID: UUID
    ) {
        guard let webView, isActive(renderID, in: webView) else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 1_280, height: 720)
        configuration.snapshotWidth = 2_560
        scheduleStepTimeout(
            "WebKit did not capture slide \(index + 1).",
            renderID: renderID
        )
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self,
                let webView = self.webView,
                self.isActive(renderID, in: webView)
            else {
                return
            }
            self.cancelStepTimeout()
            do {
                if let error {
                    throw error
                }
                guard let image,
                    image.isValid,
                    self.snapshotContainsExpectedContent(image, diagnostics: diagnostics)
                else {
                    throw RenderError.pageCreationFailed(
                        "WebKit returned an invalid slide snapshot."
                    )
                }
                image.size = NSSize(width: 1_280, height: 720)
                guard let page = PDFPage(image: image) else {
                    throw RenderError.pageCreationFailed(
                        "Could not create a PDF page from the slide snapshot."
                    )
                }
                page.setBounds(
                    CGRect(x: 0, y: 0, width: 1_280, height: 720),
                    for: .mediaBox
                )
                self.onDiagnostics?(index, diagnostics)
                output.insert(page, at: output.pageCount)
                let nextIndex = index + 1
                guard nextIndex < slideCount else {
                    self.finishDocument(
                        output,
                        expectedPageCount: slideCount,
                        renderID: renderID
                    )
                    return
                }
                self.renderPrintSlide(at: nextIndex, renderID: renderID) {
                    self.createPDFPage(
                        slideCount: slideCount,
                        index: nextIndex,
                        output: output,
                        renderID: renderID
                    )
                }
            } catch let error as RenderError {
                self.complete(.failure(error), renderID: renderID)
            } catch {
                self.complete(
                    .failure(
                        RenderError.pageCreationFailed(
                            error.localizedDescription
                        )
                    ),
                    renderID: renderID
                )
            }
        }
    }

    private func isActive(_ renderID: UUID, in webView: WKWebView) -> Bool {
        activeRenderID == renderID
            && completion != nil
            && self.webView === webView
    }

    private func scheduleStepTimeout(_ details: String, renderID: UUID) {
        cancelStepTimeout()
        let generation = UUID()
        stepTimeoutGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                    self.stepTimeoutGeneration == generation,
                    let webView = self.webView,
                    self.isActive(renderID, in: webView)
                else {
                    return
                }
                self.complete(
                    .failure(RenderError.timedOut(details)),
                    renderID: renderID
                )
            }
        }
        stepTimeout = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.stepTimeoutSeconds,
            execute: item
        )
    }

    private func cancelStepTimeout() {
        stepTimeoutGeneration = nil
        stepTimeout?.cancel()
        stepTimeout = nil
    }

    private func snapshotContainsExpectedContent(
        _ image: NSImage,
        diagnostics: String
    ) -> Bool {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ),
            cgImage.width >= 1_280,
            cgImage.height >= 720,
            abs(Double(cgImage.width) / Double(cgImage.height) - 16.0 / 9.0) < 0.001,
            let diagnosticsData = diagnostics.data(using: .utf8),
            let values = try? JSONSerialization.jsonObject(
                with: diagnosticsData
            ) as? [String: Any]
        else {
            return false
        }

        let expectsVisibleContent =
            (values["textLength"] as? Int ?? 0) > 0
            || !(values["images"] as? [Any] ?? []).isEmpty
            || !(values["diagrams"] as? [Any] ?? []).isEmpty
        guard expectsVisibleContent else { return true }
        guard let data = cgImage.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return false
        }

        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
        let sampleStepX = max(cgImage.width / 64, 1)
        let sampleStepY = max(cgImage.height / 36, 1)
        var minimum = 255
        var maximum = 0
        for y in stride(from: 0, to: cgImage.height, by: sampleStepY) {
            for x in stride(from: 0, to: cgImage.width, by: sampleStepX) {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                for channel in 0..<min(bytesPerPixel, 3) {
                    let value = Int(bytes[offset + channel])
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                }
            }
        }
        return maximum - minimum >= 8
    }

    private func complete(
        _ result: Result<PDFDocument, Error>,
        renderID: UUID
    ) {
        guard activeRenderID == renderID, let completion else { return }
        cancelStepTimeout()
        self.completion = nil
        activeRenderID = nil
        activeNavigation = nil
        completion(result)
    }

    private func cleanup() {
        cancelStepTimeout()
        guard let webView, let renderWindow else {
            self.webView = nil
            self.renderWindow = nil
            return
        }
        webView.stopLoading()
        renderWindow.close()
        activeNavigation = nil
        self.webView = nil
        self.renderWindow = nil
    }
}
