import AppKit
import WebKit

@MainActor
final class SlideWebView: NSView, WKNavigationDelegate, WKUIDelegate {
    static let canonicalSize = NSSize(width: 1_280, height: 720)

    let webView: WKWebView
    private let canvasView = NSView(
        frame: NSRect(origin: .zero, size: canonicalSize)
    )
    private let allowedOrigin: URL
    var canonicalCanvasFrame: NSRect { canvasView.frame }

    init(allowedOrigin: URL) {
        self.allowedOrigin = allowedOrigin
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = NoMenuWebView(
            frame: NSRect(origin: .zero, size: Self.canonicalSize),
            configuration: configuration
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        canvasView.bounds = NSRect(origin: .zero, size: Self.canonicalSize)
        canvasView.addSubview(webView)
        addSubview(canvasView)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        webView.isInspectable = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else {
            canvasView.frame = .zero
            return
        }

        let scale = min(
            bounds.width / Self.canonicalSize.width,
            bounds.height / Self.canonicalSize.height
        )
        let displaySize = NSSize(
            width: Self.canonicalSize.width * scale,
            height: Self.canonicalSize.height * scale
        )
        canvasView.frame = NSRect(
            x: (bounds.width - displaySize.width) / 2,
            y: (bounds.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        canvasView.bounds = NSRect(origin: .zero, size: Self.canonicalSize)
        webView.frame = canvasView.bounds
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func reload() {
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        if Self.sameOrigin(url, allowedOrigin) {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated,
            ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url,
            ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reloadFromOrigin()
    }

    private static func sameOrigin(_ left: URL, _ right: URL) -> Bool {
        left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased() && left.port == right.port
    }
}

private final class NoMenuWebView: WKWebView {
    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }
}
