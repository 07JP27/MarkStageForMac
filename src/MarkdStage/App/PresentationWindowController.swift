import AppKit
import UniformTypeIdentifiers

@MainActor
final class PresentationWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations, @unchecked Sendable {
    private let session: PresentationSession
    private let server: PresentationServer
    private let loader = DeckLoader()
    private let watcher = DeckWatcher()
    private var observerID: UUID?
    private var currentURL: URL?
    private var loadGeneration = 0
    private var audienceWindowController: AudienceWindowController?
    private var exportCoordinator: PDFExportCoordinator?

    private let currentSlideView: SlideWebView
    private let nextSlideView: SlideWebView
    private let emptyState = EmptyStateView()
    private let fileNameLabel = NSTextField(labelWithString: "No Markdown file selected")
    private let errorLabel = NSTextField(labelWithString: "")
    private let pageCounter = NSTextField(labelWithString: "0 / 0")
    private let notesTextView = NSTextView()
    private let nextPlaceholder = NSTextField(labelWithString: "There is no next slide")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let overviewButton = NSButton()
    private let presentButton = NSButton()
    private let exportButton = NSButton()
    private let liveStatusLabel = NSTextField(labelWithString: "Open a deck to begin")
    private var overviewTitles: [String] = []
    private var currentDeckVersion: Int64 = -1

    init(session: PresentationSession, server: PresentationServer) {
        self.session = session
        self.server = server
        let baseURL = server.baseURL!
        currentSlideView = SlideWebView(allowedOrigin: baseURL)
        nextSlideView = SlideWebView(allowedOrigin: baseURL)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MarkdStage"
        window.minSize = NSSize(width: 960, height: 640)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)
        window.delegate = self
        setupInterface()
        loadRenderer()

        emptyState.onOpen = { [weak self] in self?.openDocument(nil) }
        (window.contentView as? DeckDropView)?.onDeckDropped = { [weak self] url in
            self?.loadDeck(at: url, startWatching: true)
        }
        observerID = session.addObserver { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openInitialDeck(_ url: URL) {
        loadDeck(at: url, startWatching: true)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadDeck(at: url, startWatching: true)
        }
    }

    @objc func previousSlide(_ sender: Any?) {
        session.navigate(by: -1)
    }

    @objc func nextSlide(_ sender: Any?) {
        session.navigate(by: 1)
    }

    @objc func firstSlide(_ sender: Any?) {
        session.navigate(to: 0)
    }

    @objc func lastSlide(_ sender: Any?) {
        let snapshot = session.currentSnapshot()
        if snapshot.total > 0 {
            session.navigate(to: snapshot.total - 1)
        }
    }

    @objc func showSlideList(_ sender: Any?) {
        let snapshot = session.currentSnapshot()
        guard snapshot.total > 0, let window else { return }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 30))
        for (index, title) in overviewTitles.enumerated() {
            popup.addItem(withTitle: "\(index + 1)   \(title)")
        }
        popup.selectItem(at: snapshot.index)

        let alert = NSAlert()
        alert.messageText = "Slide List"
        alert.informativeText = "Choose the slide to show."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Go to Slide")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.session.navigate(to: popup.indexOfSelectedItem)
        }
    }

    @objc func togglePresentation(_ sender: Any?) {
        if let audienceWindowController {
            audienceWindowController.close()
            self.audienceWindowController = nil
            server.setPresenterRunning(false)
            updatePresenterButton()
            return
        }
        guard let baseURL = server.baseURL else { return }
        let controller = AudienceWindowController(baseURL: baseURL)
        controller.onClose = { [weak self, weak controller] in
            guard let self, self.audienceWindowController === controller else { return }
            self.audienceWindowController = nil
            self.server.setPresenterRunning(false)
            self.updatePresenterButton()
        }
        audienceWindowController = controller
        server.setPresenterRunning(true)
        controller.showWindow(sender)
        updatePresenterButton()
    }

    @objc func toggleAudienceFullScreen(_ sender: Any?) {
        audienceWindowController?.window?.toggleFullScreen(sender)
    }

    @objc func exportPDF(_ sender: Any?) {
        guard session.currentSnapshot().total > 0,
              let window,
              let baseURL = server.baseURL,
              exportCoordinator == nil else {
            NSSound.beep()
            return
        }
        let stem = currentURL?.deletingPathExtension().lastPathComponent ?? "MarkdStage"
        let coordinator = PDFExportCoordinator(
            parentWindow: window,
            baseURL: baseURL,
            onCompletion: { [weak self] in
                self?.exportCoordinator = nil
            }
        ) { [weak self] status in
            self?.liveStatusLabel.stringValue = status
        }
        exportCoordinator = coordinator
        coordinator.export(suggestedName: "\(stem).pdf")
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let snapshot = session.currentSnapshot()
        switch item.action {
        case #selector(previousSlide(_:)), #selector(firstSlide(_:)):
            guard navigationKeysAreAvailable else { return false }
            return snapshot.total > 0 && snapshot.index > 0
        case #selector(nextSlide(_:)), #selector(lastSlide(_:)):
            guard navigationKeysAreAvailable else { return false }
            return snapshot.hasNext
        case #selector(showSlideList(_:)), #selector(togglePresentation(_:)), #selector(exportPDF(_:)):
            return snapshot.total > 0
        case #selector(toggleAudienceFullScreen(_:)):
            return audienceWindowController != nil
        default:
            return true
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher.stop()
        audienceWindowController?.close()
        if let observerID {
            session.removeObserver(observerID)
            self.observerID = nil
        }
    }

    private func setupInterface() {
        guard let window else { return }
        let root = DeckDropView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = root

        let header = makeHeader()
        let errorBar = makeErrorBar()
        let content = makeContent()
        let footer = makeFooter()

        let stack = NSStackView(views: [header, errorBar, content, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 58),
            footer.heightAnchor.constraint(equalToConstant: 54)
        ])
        errorBar.isHidden = true
        errorLabel.tag = 7001
    }

    private func makeHeader() -> NSView {
        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active

        let openButton = makeButton(
            title: "Open",
            symbol: "folder",
            action: #selector(openDocument(_:))
        )
        configure(
            overviewButton,
            title: "Slide List",
            symbol: "list.number",
            action: #selector(showSlideList(_:))
        )
        configure(
            presentButton,
            title: "Start Presentation",
            symbol: "play.rectangle",
            action: #selector(togglePresentation(_:))
        )
        configure(
            exportButton,
            title: "Export PDF",
            symbol: "square.and.arrow.down",
            action: #selector(exportPDF(_:))
        )

        fileNameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fileNameLabel.textColor = .secondaryLabelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controls = NSStackView(views: [openButton, overviewButton, presentButton, exportButton])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(fileNameLabel)
        header.addSubview(controls)

        NSLayoutConstraint.activate([
            fileNameLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            fileNameLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            controls.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 8),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: fileNameLabel.trailingAnchor, constant: 20)
        ])
        return header
    }

    private func makeErrorBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 32),
            errorLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            errorLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    private func makeContent() -> NSView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MarkdStageOperatorSplit"

        let currentShell = paneShell()
        let currentAspect = AspectRatioView(contentView: currentSlideView)
        currentAspect.translatesAutoresizingMaskIntoConstraints = false
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        currentShell.addSubview(currentAspect)
        currentShell.addSubview(emptyState)
        NSLayoutConstraint.activate([
            currentAspect.leadingAnchor.constraint(equalTo: currentShell.leadingAnchor, constant: 16),
            currentAspect.trailingAnchor.constraint(equalTo: currentShell.trailingAnchor, constant: -16),
            currentAspect.topAnchor.constraint(equalTo: currentShell.topAnchor, constant: 16),
            currentAspect.bottomAnchor.constraint(equalTo: currentShell.bottomAnchor, constant: -16),
            emptyState.leadingAnchor.constraint(equalTo: currentShell.leadingAnchor, constant: 16),
            emptyState.trailingAnchor.constraint(equalTo: currentShell.trailingAnchor, constant: -16),
            emptyState.topAnchor.constraint(equalTo: currentShell.topAnchor, constant: 16),
            emptyState.bottomAnchor.constraint(equalTo: currentShell.bottomAnchor, constant: -16),
            currentShell.widthAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])

        let nextAspect = AspectRatioView(contentView: nextSlideView)
        let nextPane = titledPane(title: "NEXT SLIDE", content: nextAspect)
        nextPlaceholder.textColor = .secondaryLabelColor
        nextPlaceholder.alignment = .center
        nextPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        nextPane.addSubview(nextPlaceholder)
        NSLayoutConstraint.activate([
            nextPlaceholder.centerXAnchor.constraint(equalTo: nextPane.centerXAnchor),
            nextPlaceholder.centerYAnchor.constraint(equalTo: nextPane.centerYAnchor)
        ])

        notesTextView.isEditable = false
        notesTextView.isSelectable = true
        notesTextView.drawsBackground = false
        notesTextView.font = .systemFont(ofSize: 14)
        notesTextView.textContainerInset = NSSize(width: 8, height: 8)
        notesTextView.string = "No speaker notes"
        let notesScroll = NSScrollView()
        notesScroll.hasVerticalScroller = true
        notesScroll.autohidesScrollers = true
        notesScroll.documentView = notesTextView
        let notesPane = titledPane(title: "SPEAKER NOTES", content: notesScroll)

        let side = NSStackView(views: [nextPane, notesPane])
        side.orientation = .vertical
        side.alignment = .width
        side.distribution = .fillEqually
        side.spacing = 12
        side.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        side.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        splitView.addArrangedSubview(currentShell)
        splitView.addArrangedSubview(side)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        DispatchQueue.main.async {
            splitView.setPosition(850, ofDividerAt: 0)
        }
        return splitView
    }

    private func makeFooter() -> NSView {
        let footer = NSVisualEffectView()
        footer.material = .menu
        footer.blendingMode = .withinWindow

        configure(previousButton, title: "Previous", symbol: "chevron.left", action: #selector(previousSlide(_:)))
        configure(nextButton, title: "Next", symbol: "chevron.right", action: #selector(nextSlide(_:)))
        pageCounter.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        pageCounter.alignment = .center
        pageCounter.setContentHuggingPriority(.required, for: .horizontal)

        let controls = NSStackView(views: [previousButton, pageCounter, nextButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 18
        controls.translatesAutoresizingMaskIntoConstraints = false

        liveStatusLabel.font = .systemFont(ofSize: 11)
        liveStatusLabel.textColor = .secondaryLabelColor
        liveStatusLabel.lineBreakMode = .byTruncatingMiddle
        liveStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(controls)
        footer.addSubview(liveStatusLabel)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            liveStatusLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 18),
            liveStatusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            liveStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -18)
        ])
        return footer
    }

    private func titledPane(title: String, content: NSView) -> NSView {
        let shell = paneShell()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(label)
        shell.addSubview(content)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: shell.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -10)
        ])
        return shell
    }

    private func paneShell() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        return view
    }

    private func makeButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        configure(button, title: title, symbol: symbol, action: action)
        return button
    }

    private func configure(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
    }

    private func loadRenderer() {
        guard let baseURL = server.baseURL else { return }
        var current = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        current.queryItems = [
            URLQueryItem(name: "preview", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "navigate", value: "1")
        ]
        var next = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        next.queryItems = [
            URLQueryItem(name: "preview", value: "1"),
            URLQueryItem(name: "offset", value: "1")
        ]
        currentSlideView.load(current.url!)
        nextSlideView.load(next.url!)
    }

    private func loadDeck(at url: URL, startWatching: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        liveStatusLabel.stringValue = "Loading \(url.lastPathComponent)…"
        let loader = self.loader

        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try loader.load(url)
                }.value
                guard generation == loadGeneration else { return }
                currentURL = loaded.sourceURL
                session.load(
                    loaded.document,
                    sourceURL: loaded.sourceURL,
                    workspaceRoot: loaded.workspaceRoot,
                    theme: loaded.theme
                )
                fileNameLabel.stringValue = loaded.sourceURL.lastPathComponent
                window?.title = "\(loaded.sourceURL.lastPathComponent) — MarkdStage"
                clearError()
                NSDocumentController.shared.noteNewRecentDocumentURL(loaded.sourceURL)
                if startWatching {
                    do {
                        try watcher.start(fileURL: loaded.sourceURL) { [weak self] in
                            self?.reloadCurrentDeck()
                        }
                        liveStatusLabel.stringValue = "Live reload on"
                    } catch {
                        showError(error.localizedDescription)
                        liveStatusLabel.stringValue = "Live reload unavailable"
                    }
                } else {
                    liveStatusLabel.stringValue = "Updated from disk"
                }
            } catch {
                guard generation == loadGeneration else { return }
                let suffix = session.currentSnapshot().total > 0
                    ? " The last successfully rendered deck is still displayed."
                    : ""
                showError(error.localizedDescription + suffix)
                liveStatusLabel.stringValue = "Couldn’t load \(url.lastPathComponent)"
            }
        }
    }

    private func reloadCurrentDeck() {
        guard let currentURL else { return }
        loadDeck(at: currentURL, startWatching: false)
    }

    private func apply(_ snapshot: PresentationSnapshot) {
        let loaded = snapshot.total > 0
        emptyState.isHidden = loaded
        previousButton.isEnabled = loaded && snapshot.index > 0
        nextButton.isEnabled = snapshot.hasNext
        overviewButton.isEnabled = loaded
        presentButton.isEnabled = loaded
        exportButton.isEnabled = loaded
        pageCounter.stringValue = loaded ? "\(snapshot.index + 1) / \(snapshot.total)" : "0 / 0"
        let notes = SpeakerNotesExtractor.extract(snapshot.currentMarkdown)
        notesTextView.string = notes.isEmpty ? "No speaker notes" : notes
        notesTextView.textColor = notes.isEmpty ? .secondaryLabelColor : .labelColor
        nextPlaceholder.isHidden = snapshot.hasNext
        nextSlideView.isHidden = !snapshot.hasNext
        if snapshot.deckVersion != currentDeckVersion {
            currentDeckVersion = snapshot.deckVersion
            overviewTitles = snapshot.slides.map(SlideTitleDeriver.derive)
        }
        updatePresenterButton()
    }

    private func updatePresenterButton() {
        let running = audienceWindowController != nil
        presentButton.title = running ? "End Presentation" : "Start Presentation"
        presentButton.image = NSImage(
            systemSymbolName: running ? "stop.rectangle" : "play.rectangle",
            accessibilityDescription: presentButton.title
        )
        presentButton.setAccessibilityLabel(presentButton.title)
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.superview?.isHidden = false
    }

    private func clearError() {
        errorLabel.stringValue = ""
        errorLabel.superview?.isHidden = true
    }

    private var navigationKeysAreAvailable: Bool {
        guard window?.attachedSheet == nil else { return false }
        return !(NSApp.keyWindow?.firstResponder is NSTextView)
    }
}
