import AppKit

@MainActor
final class EmptyStateView: NSView {
    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 11 / 255, green: 16 / 255, blue: 32 / 255, alpha: 1).setFill()
        dirtyRect.fill()

        let spotlight = NSBezierPath()
        spotlight.move(to: NSPoint(x: bounds.maxX * 0.82, y: bounds.maxY))
        spotlight.line(to: NSPoint(x: bounds.maxX * 0.52, y: 0))
        spotlight.line(to: NSPoint(x: bounds.maxX, y: 0))
        spotlight.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        spotlight.close()
        NSColor(calibratedRed: 1, green: 181 / 255, blue: 71 / 255, alpha: 0.15).setFill()
        spotlight.fill()
    }

    private func setupContent() {
        let title = NSTextField(labelWithString: "Markdown, ready\nfor the stage.")
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = NSColor(calibratedRed: 247 / 255, green: 244 / 255, blue: 237 / 255, alpha: 1)
        title.maximumNumberOfLines = 2

        let subtitle = NSTextField(labelWithString: "Open a Markdown deck to preview, present, and stay in sync while you edit.")
        subtitle.font = .systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = NSColor(calibratedRed: 200 / 255, green: 206 / 255, blue: 221 / 255, alpha: 1)
        subtitle.maximumNumberOfLines = 3
        subtitle.preferredMaxLayoutWidth = 380

        let openButton = NSButton(title: "Open Markdown", target: self, action: #selector(openDocument))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        openButton.contentTintColor = NSColor(calibratedRed: 1, green: 181 / 255, blue: 71 / 255, alpha: 1)
        openButton.setAccessibilityLabel("Open Markdown")

        let copy = NSStackView(views: [title, subtitle, openButton])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 16
        copy.setCustomSpacing(24, after: subtitle)
        copy.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copy)

        let mark = NSTextField(labelWithString: "#")
        mark.font = .systemFont(ofSize: 190, weight: .black)
        mark.textColor = NSColor(calibratedRed: 1, green: 215 / 255, blue: 122 / 255, alpha: 0.96)
        mark.alignment = .center
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        NSLayoutConstraint.activate([
            copy.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            copy.centerYAnchor.constraint(equalTo: centerYAnchor),
            copy.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),
            mark.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.3),
            mark.leadingAnchor.constraint(greaterThanOrEqualTo: copy.trailingAnchor, constant: 24)
        ])
    }

    @objc private func openDocument() {
        onOpen?()
    }
}
