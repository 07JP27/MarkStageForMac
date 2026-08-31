#if DEBUG
import AppKit
import Darwin
import Foundation
import PDFKit

@MainActor
final class PDFSmokeRunner: NSObject, NSApplicationDelegate {
    private static let flag = "--pdf-smoke"

    private let arguments: [String]
    private var renderer: DeckPDFRenderer?
    private var server: PresentationServer?
    private var session: PresentationSession?
    private var parityValidator: RendererParityValidator?
    private var printDiagnostics: [Int: String] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    init?(arguments: [String]) {
        guard arguments.dropFirst().first == Self.flag else { return nil }
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard arguments.count == 4 else {
                throw SmokeError(
                    message: "Usage: MarkdStage \(Self.flag) <deck-path> <output-pdf>"
                )
            }

            let deckURL = URL(fileURLWithPath: arguments[2])
            let outputURL = URL(fileURLWithPath: arguments[3])
            let loadedDeck = try DeckLoader().load(deckURL)
            guard loadedDeck.document.slides.count > 1 else {
                throw SmokeError(message: "PDF smoke requires a deck with at least two slides.")
            }
            startTimeout(slideCount: loadedDeck.document.slides.count)

            let session = PresentationSession()
            session.load(
                loadedDeck.document,
                sourceURL: loadedDeck.sourceURL,
                workspaceRoot: loadedDeck.workspaceRoot,
                theme: loadedDeck.theme
            )
            self.session = session

            let server = try PresentationServer(session: session)
            try server.start()
            guard let baseURL = server.baseURL else {
                throw SmokeError(message: "Presentation server did not provide a renderer URL.")
            }
            self.server = server

            let renderer = DeckPDFRenderer(
                parentWindow: nil,
                baseURL: baseURL,
                onDiagnostics: { [weak self] index, diagnostics in
                    self?.printDiagnostics[index] = diagnostics
                }
            )
            self.renderer = renderer
            renderer.render { [weak self] result in
                self?.handle(
                    result,
                    expectedPageCount: loadedDeck.document.slides.count,
                    outputURL: outputURL
                )
            }
        } catch {
            finish(
                message: "PDF smoke failed: \(error.localizedDescription)",
                exitCode: 1,
                toStandardError: true
            )
        }
    }

    private func startTimeout(slideCount: Int) {
        let seconds = max(UInt64(slideCount) * 15, 120)
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            self?.finish(
                message: "PDF smoke failed: rendering exceeded \(seconds) seconds.",
                exitCode: 124,
                toStandardError: true
            )
        }
    }

    private func handle(
        _ result: Result<PDFDocument, Error>,
        expectedPageCount: Int,
        outputURL: URL
    ) {
        do {
            let document = try result.get()
            guard document.pageCount == expectedPageCount else {
                throw SmokeError(
                    message:
                        "Expected \(expectedPageCount) pages, rendered \(document.pageCount)."
                )
            }
            guard let data = document.dataRepresentation(),
                data.starts(with: Data("%PDF".utf8))
            else {
                throw SmokeError(message: "WebKit returned invalid PDF data.")
            }
            try data.write(to: outputURL, options: .atomic)
            guard let session,
                let baseURL = server?.baseURL
            else {
                throw SmokeError(message: "PDF parity renderer state is unavailable.")
            }
            let diagnosticsDirectory =
                outputURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    outputURL.deletingPathExtension().lastPathComponent + "-parity",
                    isDirectory: true
                )
            let validator = RendererParityValidator(
                baseURL: baseURL,
                session: session,
                expectedDiagnostics: printDiagnostics,
                diagnosticsDirectory: diagnosticsDirectory,
                completion: { [weak self] result in
                    switch result {
                    case .success:
                        self?.finish(
                            message: "PDF smoke succeeded with visual parity: "
                                + "\(document.pageCount) pages at \(outputURL.path)",
                            exitCode: 0,
                            toStandardError: false
                        )
                    case .failure(let error):
                        self?.finish(
                            message: "PDF smoke failed: \(error.localizedDescription)",
                            exitCode: 1,
                            toStandardError: true
                        )
                    }
                }
            )
            parityValidator = validator
            validator.start()
        } catch {
            finish(
                message: "PDF smoke failed: \(error.localizedDescription)",
                exitCode: 1,
                toStandardError: true
            )
        }
    }

    private func finish(
        message: String,
        exitCode: Int32,
        toStandardError: Bool
    ) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()

        let handle =
            toStandardError
            ? FileHandle.standardError
            : FileHandle.standardOutput
        handle.write(Data("\(message)\n".utf8))
        FileHandle.standardOutput.synchronizeFile()
        FileHandle.standardError.synchronizeFile()
        fflush(nil)

        // Do not tear down WKWebView in-process; the smoke test exists specifically
        // to isolate WebKit lifetime from the test host.
        _exit(exitCode)
    }
}

private struct SmokeError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
#endif
