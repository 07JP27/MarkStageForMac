import Darwin
import Foundation

@MainActor
final class DeckWatcher: @unchecked Sendable {
    private var watchedURL: URL?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var pendingFileRearm = false
    private var onChange: (() -> Void)?

    func start(fileURL: URL, onChange: @escaping () -> Void) throws {
        stop()
        watchedURL = PathSecurity.canonicalURL(fileURL)
        self.onChange = onChange

        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw DeckLoadError(message: "Could not monitor Markdown saves.")
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChange(rearmFile: true)
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        directorySource = source
        source.resume()

        do {
            try armFileSource()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
        watchedURL = nil
        pendingFileRearm = false
        onChange = nil
    }

    private func armFileSource() throws {
        fileSource?.cancel()
        fileSource = nil
        guard let watchedURL else { return }
        let descriptor = open(watchedURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw DeckLoadError(message: "Could not monitor Markdown saves.")
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            let shouldRearm = event.contains(.rename) ||
                event.contains(.delete) ||
                event.contains(.revoke)
            self?.scheduleChange(rearmFile: shouldRearm)
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        fileSource = source
        source.resume()
    }

    private func scheduleChange(rearmFile: Bool) {
        pendingFileRearm = pendingFileRearm || rearmFile
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingFileRearm {
                self.pendingFileRearm = false
                try? self.armFileSource()
            }
            self.onChange?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }
}
