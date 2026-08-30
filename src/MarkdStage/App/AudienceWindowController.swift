import AppKit

@MainActor
final class AudienceWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let slideView: SlideWebView

    init(baseURL: URL) {
        slideView = SlideWebView(allowedOrigin: baseURL)
        let targetScreen = NSScreen.screens.first(where: { $0 != NSScreen.main }) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let size = Self.presentationSize(fitting: visibleFrame.size)
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.title = "MarkdStage — Audience"
        window.minSize = NSSize(width: 640, height: 360)
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = slideView
        super.init(window: window)
        window.delegate = self

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "present", value: "1")]
        slideView.load(components.url!)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(slideView.webView)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private static func presentationSize(fitting available: NSSize) -> NSSize {
        var width = min(1280, available.width * 0.88)
        var height = width * 9 / 16
        if height > available.height * 0.88 {
            height = available.height * 0.88
            width = height * 16 / 9
        }
        return NSSize(width: width, height: height)
    }
}
