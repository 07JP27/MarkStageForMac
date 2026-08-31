import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class PDFExportCoordinator: NSObject {
    private weak var parentWindow: NSWindow?
    private let baseURL: URL
    private let preparedDocument: PDFDocument?
    private let onCompletion: () -> Void
    private let onStatus: (String) -> Void
    private var outputURL: URL?
    private var renderer: DeckPDFRenderer?

    init(
        parentWindow: NSWindow,
        baseURL: URL,
        preparedDocument: PDFDocument? = nil,
        onCompletion: @escaping () -> Void = {},
        onStatus: @escaping (String) -> Void
    ) {
        self.parentWindow = parentWindow
        self.baseURL = baseURL
        self.preparedDocument = preparedDocument
        self.onCompletion = onCompletion
        self.onStatus = onStatus
    }

    func export(suggestedName: String) {
        guard renderer == nil, let parentWindow else { return }
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
        guard renderer == nil else { return }
        outputURL = url
        onStatus("Preparing PDF…")
        if let preparedDocument {
            save(preparedDocument)
            return
        }

        let renderer = DeckPDFRenderer(
            parentWindow: parentWindow,
            baseURL: baseURL
        )
        self.renderer = renderer
        renderer.render { [weak self, weak renderer] result in
            guard let self,
                  let renderer,
                  self.renderer === renderer else {
                return
            }
            switch result {
            case let .success(document):
                self.save(document)
            case let .failure(error):
                if error is CancellationError {
                    self.finish()
                } else {
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func save(_ document: PDFDocument) {
        guard let outputURL else {
            fail("Could not save the PDF: The output location is unavailable.")
            return
        }
        do {
            guard let data = document.dataRepresentation() else {
                throw DeckLoadError(message: "WebKit returned an empty PDF.")
            }
            try data.write(to: outputURL, options: .atomic)
            onStatus("Saved \(outputURL.lastPathComponent)")
            finish()
        } catch {
            fail("Could not save the PDF: \(error.localizedDescription)")
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
        let renderer = self.renderer
        self.renderer = nil
        outputURL = nil
        renderer?.shutdown()
        onCompletion()
    }
}
