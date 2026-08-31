import AppKit

@MainActor
final class DeckDropView: NSView {
    var onDeckDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        deckURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = deckURL(from: sender) else { return false }
        onDeckDropped?(url)
        return true
    }

    private func deckURL(from sender: NSDraggingInfo) -> URL? {
        guard let value = sender.draggingPasteboard.string(forType: .fileURL),
              let url = URL(string: value) else {
            return nil
        }
        return ["md", "markdown"].contains(url.pathExtension.lowercased()) ? url : nil
    }
}
