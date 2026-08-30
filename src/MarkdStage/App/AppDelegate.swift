import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let session = PresentationSession()
    private var server: PresentationServer?
    private var mainWindowController: PresentationWindowController?
    private var pendingDeckURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.make(delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let server = try PresentationServer(session: session)
            try server.start()
            self.server = server
            let controller = PresentationWindowController(session: session, server: server)
            mainWindowController = controller
            controller.showWindow(nil)
            let initialURL = pendingDeckURLs.first ?? Self.initialDeckURL()
            pendingDeckURLs.removeAll()
            if let initialURL {
                controller.openInitialDeck(initialURL)
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "MarkdStage couldn’t start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let deckURLs = urls.filter(Self.isDeckURL)
        guard let controller = mainWindowController else {
            pendingDeckURLs.append(contentsOf: deckURLs)
            return
        }
        if let url = deckURLs.first {
            controller.openInitialDeck(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openDocument(_ sender: Any?) {
        mainWindowController?.openDocument(sender)
    }

    @objc func closeDocument(_ sender: Any?) {
        mainWindowController?.closeDocument(sender)
    }

    @objc func previousSlide(_ sender: Any?) {
        mainWindowController?.previousSlide(sender)
    }

    @objc func nextSlide(_ sender: Any?) {
        mainWindowController?.nextSlide(sender)
    }

    @objc func firstSlide(_ sender: Any?) {
        mainWindowController?.firstSlide(sender)
    }

    @objc func lastSlide(_ sender: Any?) {
        mainWindowController?.lastSlide(sender)
    }

    @objc func showSlideList(_ sender: Any?) {
        mainWindowController?.showSlideList(sender)
    }

    @objc func togglePresentation(_ sender: Any?) {
        mainWindowController?.togglePresentation(sender)
    }

    @objc func toggleAudienceFullScreen(_ sender: Any?) {
        mainWindowController?.toggleAudienceFullScreen(sender)
    }

    @objc func exportPDF(_ sender: Any?) {
        mainWindowController?.exportPDF(sender)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MarkdStage",
            .applicationVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.1.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: "Markdown, ready for the stage.\nmacOS port based on the authorized MarkdStage source."
            )
        ])
    }

    @objc func openProjectWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/07JP27/MarkdstageForMac")!)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let mainWindowController else { return menuItem.action == #selector(openDocument(_:)) }
        return mainWindowController.validateUserInterfaceItem(menuItem)
    }

    private static func initialDeckURL() -> URL? {
        CommandLine.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: $0) }
            .first(where: isDeckURL)
    }

    private static func isDeckURL(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }
}
