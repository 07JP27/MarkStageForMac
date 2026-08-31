import AppKit

@MainActor
final class EmptyStateView: NSVisualEffectView {
    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func setupContent() {
        let icon = NSImageView()
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 38, weight: .regular)
        icon.image = NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)

        let title = NSTextField(labelWithString: "No Markdown file open")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let subtitle = NSTextField(
            labelWithString: "Choose File > Open… or drag a Markdown file here."
        )
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 360

        let openButton = NSButton(
            title: "Open Markdown…",
            target: self,
            action: #selector(openDocument)
        )
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        openButton.setAccessibilityLabel("Open Markdown")

        let stack = NSStackView(views: [icon, title, subtitle, openButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func openDocument() {
        onOpen?()
    }
}
