import AppKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class PDFExportCoordinator: NSObject, WKNavigationDelegate {
    private weak var parentWindow: NSWindow?
    private let baseURL: URL
    private let onCompletion: () -> Void
    private let onStatus: (String) -> Void
    private var outputURL: URL?
    private var webView: WKWebView?
    private var renderWindow: NSWindow?

    init(
        parentWindow: NSWindow,
        baseURL: URL,
        onCompletion: @escaping () -> Void = {},
        onStatus: @escaping (String) -> Void
    ) {
        self.parentWindow = parentWindow
        self.baseURL = baseURL
        self.onCompletion = onCompletion
        self.onStatus = onStatus
    }

    func export(suggestedName: String) {
        guard webView == nil, let parentWindow else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                self?.finish()
                return
            }
            self?.export(to: url)
        }
    }

    func export(to url: URL) {
        guard webView == nil else { return }
        outputURL = url
        onStatus("Preparing PDF…")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        webView.navigationDelegate = self
        webView.isInspectable = false
        let origin = parentWindow?.frame.origin ?? .zero
        let window = NSWindow(
            contentRect: NSRect(x: origin.x + 24, y: origin.y + 24, width: 1280, height: 720),
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

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "print", value: "1"),
            URLQueryItem(name: "token", value: UUID().uuidString)
        ]
        webView.load(URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitUntilReady(attempt: 0)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        fail("PDF renderer failed to load: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail("PDF renderer failed to load: \(error.localizedDescription)")
    }

    private func waitUntilReady(attempt: Int) {
        guard let webView else { return }
        guard attempt < 150 else {
            diagnoseTimeout(in: webView)
            return
        }
        webView.evaluateJavaScript(
            "Boolean(window.__presentationPrintReady)"
        ) { [weak self] result, error in
            guard let self else { return }
            if error == nil, result as? Bool == true {
                self.createPDF()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.waitUntilReady(attempt: attempt + 1)
            }
        }
    }

    private func diagnoseTimeout(in webView: WKWebView) {
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
            let details = result as? String ?? "page state unavailable"
            self?.fail("PDF rendering timed out. \(details)")
        }
    }

    private func createPDF() {
        guard let webView else { return }
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
            guard let self else { return }
            guard error == nil,
                  let values = result as? [[String: Any]] else {
                self.fail("Could not measure the rendered PDF pages.")
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
                self.fail("The rendered deck did not contain printable slides.")
                return
            }
            self.createPDFPage(
                rects: rects,
                index: 0,
                output: PDFDocument()
            )
        }
    }

    private func createPDFPage(rects: [CGRect], index: Int, output: PDFDocument) {
        guard let webView, let outputURL else { return }
        guard index < rects.count else {
            do {
                guard let data = output.dataRepresentation() else {
                    throw DeckLoadError(message: "WebKit returned an empty PDF.")
                }
                try data.write(to: outputURL, options: .atomic)
                onStatus("Saved \(outputURL.lastPathComponent)")
                finish()
            } catch {
                fail("Could not save the PDF: \(error.localizedDescription)")
            }
            return
        }

        let configuration = WKPDFConfiguration()
        configuration.rect = rects[index]
        webView.createPDF(configuration: configuration) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let data = try result.get()
                    guard let pageDocument = PDFDocument(data: data),
                          pageDocument.pageCount == 1,
                          let page = pageDocument.page(at: 0)?.copy() as? PDFPage else {
                        throw DeckLoadError(message: "WebKit returned an invalid PDF page.")
                    }
                    output.insert(page, at: output.pageCount)
                    self.createPDFPage(rects: rects, index: index + 1, output: output)
                } catch {
                    self.fail("Could not save the PDF: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fail(_ message: String) {
        onStatus(message)
        if let parentWindow {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t save the PDF"
            alert.informativeText = message
            alert.beginSheetModal(for: parentWindow)
        }
        finish()
    }

    private func finish() {
        webView?.stopLoading()
        renderWindow?.close()
        webView = nil
        renderWindow = nil
        outputURL = nil
        onCompletion()
    }
}
