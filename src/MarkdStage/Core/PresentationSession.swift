import Foundation

final class PresentationSession: @unchecked Sendable {
    typealias Observer = @Sendable (PresentationSnapshot) -> Void

    private let lock = NSLock()
    private var snapshot = PresentationSnapshot(
        slides: [],
        index: 0,
        version: 0,
        deckVersion: 0,
        sourceURL: nil,
        workspaceRoot: nil,
        theme: ThemeState(name: "dark")
    )
    private var observers: [UUID: Observer] = [:]

    func currentSnapshot() -> PresentationSnapshot {
        lock.withLock { snapshot }
    }

    @discardableResult
    func load(
        _ document: DeckDocument,
        sourceURL: URL,
        workspaceRoot: URL,
        theme: ThemeState? = nil
    ) -> PresentationSnapshot {
        let result = lock.withLock {
            let index = document.slides.isEmpty
                ? 0
                : min(max(snapshot.index, 0), document.slides.count - 1)
            snapshot = PresentationSnapshot(
                slides: document.slides,
                index: index,
                version: snapshot.version + 1,
                deckVersion: snapshot.deckVersion + 1,
                sourceURL: sourceURL,
                workspaceRoot: workspaceRoot,
                theme: theme ?? ThemeState(name: document.theme)
            )
            return (snapshot, Array(observers.values))
        }
        result.1.forEach { $0(result.0) }
        return result.0
    }

    @discardableResult
    func navigate(by delta: Int) -> Bool {
        navigate(to: currentSnapshot().index + delta)
    }

    @discardableResult
    func navigate(to index: Int) -> Bool {
        let result: (PresentationSnapshot, [Observer])? = lock.withLock {
            guard !snapshot.slides.isEmpty else { return nil }
            let target = min(max(index, 0), snapshot.slides.count - 1)
            guard target != snapshot.index else { return nil }
            snapshot = PresentationSnapshot(
                slides: snapshot.slides,
                index: target,
                version: snapshot.version + 1,
                deckVersion: snapshot.deckVersion,
                sourceURL: snapshot.sourceURL,
                workspaceRoot: snapshot.workspaceRoot,
                theme: snapshot.theme
            )
            return (snapshot, Array(observers.values))
        }
        guard let result else { return false }
        result.1.forEach { $0(result.0) }
        return true
    }

    func addObserver(_ observer: @escaping Observer) -> UUID {
        lock.withLock {
            let id = UUID()
            observers[id] = observer
            return id
        }
    }

    func removeObserver(_ id: UUID) {
        _ = lock.withLock {
            observers.removeValue(forKey: id)
        }
    }
}
