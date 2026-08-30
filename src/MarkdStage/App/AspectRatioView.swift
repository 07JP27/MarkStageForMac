import AppKit

@MainActor
final class AspectRatioView: NSView {
    private let contentView: NSView
    private let aspectRatio: CGFloat

    init(contentView: NSView, aspectRatio: CGFloat = 16.0 / 9.0) {
        self.contentView = contentView
        self.aspectRatio = aspectRatio
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else {
            contentView.frame = .zero
            return
        }
        var width = bounds.width
        var height = width / aspectRatio
        if height > bounds.height {
            height = bounds.height
            width = height * aspectRatio
        }
        contentView.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        ).integral
    }
}
