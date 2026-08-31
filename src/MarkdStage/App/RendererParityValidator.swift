#if DEBUG
import AppKit
import Foundation
import WebKit

@MainActor
final class RendererParityValidator: NSObject, WKNavigationDelegate {
    private enum Mode: String {
        case preview
        case next
        case audience
    }

    enum ValidationError: LocalizedError {
        case missingDiagnostics(Int)
        case loadFailed(String)
        case timedOut(Int)
        case renderMismatch(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingDiagnostics(let index):
                "PDF render diagnostics are missing for slide \(index + 1)."
            case .loadFailed(let details):
                "Live renderer failed to load during PDF parity validation: \(details)"
            case .timedOut(let index):
                "Live renderer timed out on slide \(index + 1) during PDF parity validation."
            case .renderMismatch(let index, let mode):
                "PDF slide \(index + 1) has different layout or assets than the \(mode) renderer."
            }
        }
    }

    private static let hostSize = SlideWebView.canonicalSize
    private static let maximumAttempts = 150

    private let baseURL: URL
    private let session: PresentationSession
    private let expectedDiagnostics: [Int: String]
    private let diagnosticsDirectory: URL
    private let completion: @MainActor (Result<Void, Error>) -> Void
    private let webView: WKWebView
    private let window: NSWindow
    private var index = 0
    private var mode = Mode.preview
    private var activeNavigation: WKNavigation?
    private var finished = false

    init(
        baseURL: URL,
        session: PresentationSession,
        expectedDiagnostics: [Int: String],
        diagnosticsDirectory: URL,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        self.baseURL = baseURL
        self.session = session
        self.expectedDiagnostics = expectedDiagnostics
        self.diagnosticsDirectory = diagnosticsDirectory
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(
            frame: NSRect(origin: .zero, size: Self.hostSize),
            configuration: configuration
        )
        window = NSWindow(
            contentRect: NSRect(
                x: -100_000,
                y: -100_000,
                width: Self.hostSize.width,
                height: Self.hostSize.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.alphaValue = 1
        window.ignoresMouseEvents = true
        window.contentView = webView
    }

    func start() {
        guard !expectedDiagnostics.isEmpty else {
            finish(.failure(ValidationError.missingDiagnostics(0)))
            return
        }
        window.orderBack(nil)
        loadSlide(at: 0)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation, !finished else { return }
        waitUntilReady(attempt: 0)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === activeNavigation, !finished else { return }
        finish(.failure(ValidationError.loadFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === activeNavigation, !finished else { return }
        finish(.failure(ValidationError.loadFailed(error.localizedDescription)))
    }

    private func loadSlide(at index: Int) {
        guard expectedDiagnostics[index] != nil else {
            finish(.failure(ValidationError.missingDiagnostics(index)))
            return
        }
        self.index = index
        _ = session.navigate(to: mode == .next ? index - 1 : index)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else {
            finish(.failure(ValidationError.loadFailed("The renderer URL is invalid.")))
            return
        }
        switch mode {
        case .preview:
            components.queryItems = [
                URLQueryItem(name: "preview", value: "1"),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "parity", value: UUID().uuidString),
            ]
        case .next:
            components.queryItems = [
                URLQueryItem(name: "preview", value: "1"),
                URLQueryItem(name: "offset", value: "1"),
                URLQueryItem(name: "parity", value: UUID().uuidString),
            ]
        case .audience:
            components.queryItems = [
                URLQueryItem(name: "present", value: "1"),
                URLQueryItem(name: "parity", value: UUID().uuidString),
            ]
        }
        guard let url = components.url else {
            finish(.failure(ValidationError.loadFailed("The renderer URL is invalid.")))
            return
        }
        activeNavigation = webView.load(
            URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        )
    }

    private func waitUntilReady(attempt: Int) {
        guard !finished else { return }
        guard attempt < Self.maximumAttempts else {
            finish(.failure(ValidationError.timedOut(index)))
            return
        }
        let script = """
            (() => {
              const state = window.__presentationRenderState;
              if (
                !state?.ready ||
                state.index !== \(index) ||
                document.body.classList.contains("mermaid-loading") ||
                document.querySelectorAll("#stage > .deck").length !== 1
              ) {
                return "";
              }
              return JSON.stringify(state.diagnostics);
            })()
            """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, !self.finished else { return }
            if error == nil, let diagnostics = result as? String, !diagnostics.isEmpty {
                self.compare(diagnostics)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitUntilReady(attempt: attempt + 1)
            }
        }
    }

    private func compare(_ actual: String) {
        guard let expected = expectedDiagnostics[index] else {
            finish(.failure(ValidationError.missingDiagnostics(index)))
            return
        }
        guard Self.equivalentJSON(expected, actual),
            Self.isCanonical(actual)
        else {
            saveDiagnostics(expected: expected, actual: actual, index: index, mode: mode)
            finish(.failure(ValidationError.renderMismatch(index, mode.rawValue)))
            return
        }

        if mode == .preview {
            mode = .audience
            loadSlide(at: index)
            return
        }
        if mode == .audience, index > 0 {
            mode = .next
            loadSlide(at: index)
            return
        }
        mode = .preview
        let nextIndex = index + 1
        if nextIndex < expectedDiagnostics.count {
            loadSlide(at: nextIndex)
        } else {
            finish(.success(()))
        }
    }

    private func saveDiagnostics(
        expected: String,
        actual: String,
        index: Int,
        mode: Mode
    ) {
        try? FileManager.default.createDirectory(
            at: diagnosticsDirectory,
            withIntermediateDirectories: true
        )
        try? expected.write(
            to: diagnosticsDirectory.appendingPathComponent("slide-\(index + 1)-pdf.json"),
            atomically: true,
            encoding: .utf8
        )
        try? actual.write(
            to: diagnosticsDirectory.appendingPathComponent(
                "slide-\(index + 1)-\(mode.rawValue).json"
            ),
            atomically: true,
            encoding: .utf8
        )
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        activeNavigation = nil
        webView.stopLoading()
        window.close()
        completion(result)
    }

    private static func equivalentJSON(_ left: String, _ right: String) -> Bool {
        guard let leftData = left.data(using: .utf8),
            let rightData = right.data(using: .utf8),
            let leftObject = try? JSONSerialization.jsonObject(with: leftData),
            let rightObject = try? JSONSerialization.jsonObject(with: rightData)
        else {
            return false
        }
        return equivalent(leftObject, rightObject)
    }

    private static func isCanonical(_ diagnostics: String) -> Bool {
        guard let data = diagnostics.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let deck = object["deck"] as? [String: Any],
            abs(((deck["width"] as? NSNumber)?.doubleValue ?? 0) - 1_280) <= 0.01,
            abs(((deck["height"] as? NSNumber)?.doubleValue ?? 0) - 720) <= 0.01,
            object["topBarPosition"] as? String == "absolute",
            (object["assetErrors"] as? [Any] ?? []).isEmpty
        else {
            return false
        }
        let images = object["images"] as? [[String: Any]] ?? []
        let diagrams = object["diagrams"] as? [[String: Any]] ?? []
        return (images + diagrams).allSatisfy { item in
            guard let rect = item["rect"] as? [String: Any] else { return false }
            return ((rect["width"] as? NSNumber)?.doubleValue ?? 0) > 0
                && ((rect["height"] as? NSNumber)?.doubleValue ?? 0) > 0
        }
    }

    private static func equivalent(_ left: Any, _ right: Any) -> Bool {
        switch (left, right) {
        case (let left as [String: Any], let right as [String: Any]):
            guard left.keys == right.keys else { return false }
            return left.allSatisfy { key, value in
                guard let other = right[key] else { return false }
                return equivalent(value, other)
            }
        case (let left as [Any], let right as [Any]):
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy(equivalent)
        case (let left as NSNumber, let right as NSNumber):
            return abs(left.doubleValue - right.doubleValue) <= 0.01
        case (let left as NSString, let right as NSString):
            return left == right
        case (_ as NSNull, _ as NSNull):
            return true
        default:
            return false
        }
    }
}
#endif
