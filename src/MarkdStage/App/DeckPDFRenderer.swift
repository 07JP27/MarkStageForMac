import AppKit
import PDFKit
import WebKit

@MainActor
final class DeckPDFRenderer: NSObject, WKNavigationDelegate {
    enum RenderError: LocalizedError, Equatable {
        case alreadyRendering
        case invalidRenderURL
        case loadFailed(String)
        case timedOut(String)
        case measurementFailed
        case noPrintableSlides
        case pageCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRendering:
                "PDF rendering is already in progress."
            case .invalidRenderURL:
                "PDF renderer URL could not be created."
            case let .loadFailed(details):
                "PDF renderer failed to load: \(details)"
            case let .timedOut(details):
                "PDF rendering timed out. \(details)"
            case .measurementFailed:
                "Could not measure the rendered PDF pages."
            case .noPrintableSlides:
                "The rendered deck did not contain printable slides."
            case let .pageCreationFailed(details):
                "Could not save the PDF: \(details)"
            }
        }
    }

    private weak var parentWindow: NSWindow?
    private let baseURL: URL
    private var webView: WKWebView?
    private var renderWindow: NSWindow?
    private var activeNavigation: WKNavigation?
    private var activeRenderID: UUID?
    private var completion: (@MainActor (Result<PDFDocument, Error>) -> Void)?
    private var activeRetain: DeckPDFRenderer?

    init(parentWindow: NSWindow?, baseURL: URL) {
        self.parentWindow = parentWindow
        self.baseURL = baseURL
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

        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            complete(.failure(RenderError.invalidRenderURL), renderID: renderID)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "print", value: "1"),
            URLQueryItem(name: "token", value: renderID.uuidString)
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

            let origin = parentWindow?.frame.origin ?? .zero
            let window = NSWindow(
                contentRect: NSRect(
                    x: origin.x + 24,
                    y: origin.y + 24,
                    width: 1280,
                    height: 720
                ),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.alphaValue = 0.01
            window.ignoresMouseEvents = true
            window.contentView = webView
            if let parentWindow {
                window.order(.below, relativeTo: parentWindow.windowNumber)
            } else {
                window.orderBack(nil)
            }

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
              isActive(renderID, in: webView) else {
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
              isActive(renderID, in: webView) else {
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
            "Boolean(window.__presentationPrintReady)"
        ) { [weak self] result, error in
            guard let self,
                  let webView = self.webView,
                  self.isActive(renderID, in: webView) else {
                return
            }
            if error == nil, result as? Bool == true {
                self.prepareRenderedContent(renderID: renderID)
                return
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
          imageCount: document.querySelectorAll("#stage img, #stage image").length,
          mermaidCount: document.querySelectorAll("#stage .mermaid").length
        })
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self,
                  let webView = self.webView,
                  self.isActive(renderID, in: webView) else {
                return
            }
            let details = result as? String ?? "page state unavailable"
            self.complete(
                .failure(RenderError.timedOut(details)),
                renderID: renderID
            )
        }
    }

    private func prepareRenderedContent(renderID: UUID) {
        guard let webView, isActive(renderID, in: webView) else { return }
        // Resolve Mermaid's cqh max-height against each fixed slide before capture.
        let script = """
        document.querySelectorAll("#stage .mermaid svg").forEach(svg => {
          const rect = svg.getBoundingClientRect();
          const slideRect = svg.closest(".deck")?.getBoundingClientRect();
          if (rect.height === 0 && slideRect?.height > 0) {
            svg.style.setProperty("max-height", `${slideRect.height * 0.44}px`, "important");
          }
        });
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self,
                  let webView = self.webView,
                  self.isActive(renderID, in: webView) else {
                return
            }
            guard error == nil else {
                self.complete(
                    .failure(RenderError.measurementFailed),
                    renderID: renderID
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.measureSlides(renderID: renderID)
            }
        }
    }

    private func measureSlides(renderID: UUID) {
        guard let webView, isActive(renderID, in: webView) else { return }
        let script = """
        [...document.querySelectorAll("#stage > .deck")].map(slide => {
          const rect = slide.getBoundingClientRect();
          return {
            x: rect.left + window.scrollX,
            y: rect.top + window.scrollY,
            width: rect.width,
            height: rect.height
          };
        })
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self,
                  let webView = self.webView,
                  self.isActive(renderID, in: webView) else {
                return
            }
            guard error == nil,
                  let values = result as? [[String: Any]] else {
                self.complete(
                    .failure(RenderError.measurementFailed),
                    renderID: renderID
                )
                return
            }
            let rects = values.compactMap { value -> CGRect? in
                guard let x = value["x"] as? Double,
                      let y = value["y"] as? Double,
                      let width = value["width"] as? Double,
                      let height = value["height"] as? Double,
                      width > 0,
                      height > 0 else {
                    return nil
                }
                return CGRect(x: x, y: y, width: width, height: height)
            }
            guard rects.count == values.count, !rects.isEmpty else {
                self.complete(
                    .failure(RenderError.noPrintableSlides),
                    renderID: renderID
                )
                return
            }
            self.createPDFPage(
                rects: rects,
                index: 0,
                output: PDFDocument(),
                renderID: renderID
            )
        }
    }

    private func createPDFPage(
        rects: [CGRect],
        index: Int,
        output: PDFDocument,
        renderID: UUID
    ) {
        guard let webView, isActive(renderID, in: webView) else { return }
        guard index < rects.count else {
            guard output.pageCount == rects.count else {
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
                  let detachedDocument = PDFDocument(data: data) else {
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
            return
        }

        let configuration = WKPDFConfiguration()
        configuration.rect = rects[index]
        webView.createPDF(configuration: configuration) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                      let webView = self.webView,
                      self.isActive(renderID, in: webView) else {
                    return
                }
                do {
                    let data = try result.get()
                    guard let pageDocument = PDFDocument(data: data),
                          pageDocument.pageCount == 1,
                          let page = pageDocument.page(at: 0)?.copy() as? PDFPage else {
                        throw RenderError.pageCreationFailed(
                            "WebKit returned an invalid PDF page."
                        )
                    }
                    output.insert(page, at: output.pageCount)
                    self.createPDFPage(
                        rects: rects,
                        index: index + 1,
                        output: output,
                        renderID: renderID
                    )
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

    private func isActive(_ renderID: UUID, in webView: WKWebView) -> Bool {
        activeRenderID == renderID
            && completion != nil
            && self.webView === webView
    }

    private func complete(
        _ result: Result<PDFDocument, Error>,
        renderID: UUID
    ) {
        guard activeRenderID == renderID, let completion else { return }
        self.completion = nil
        activeRenderID = nil
        activeNavigation = nil
        completion(result)
    }

    private func cleanup() {
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
