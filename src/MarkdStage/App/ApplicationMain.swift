import AppKit

@main
enum ApplicationMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
#if DEBUG
        if let smokeRunner = PDFSmokeRunner(arguments: CommandLine.arguments) {
            application.setActivationPolicy(.prohibited)
            application.delegate = smokeRunner
            application.run()
            withExtendedLifetime(smokeRunner) {}
            return
        }
#endif
        let delegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
