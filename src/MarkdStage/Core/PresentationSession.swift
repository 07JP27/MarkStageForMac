import Foundation

final class PresentationSession: @unchecked Sendable {
    typealias Observer = @Sendable (PresentationSnapshot) -> Void

    private let lock = NSLock()
    private let notificationQueue = DispatchQueue(label: "dev.jp27.MarkdStage.session-observers")
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
        lock.withLock {
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
            enqueueNotification(snapshot, observers: Array(observers.values))
            return snapshot
        }
    }

    @discardableResult
    func clear() -> PresentationSnapshot {
        lock.withLock {
            snapshot = PresentationSnapshot(
                slides: [],
                index: 0,
                version: snapshot.version + 1,
                deckVersion: snapshot.deckVersion + 1,
                sourceURL: nil,
                workspaceRoot: nil,
                theme: ThemeState(name: "dark")
            )
            enqueueNotification(snapshot, observers: Array(observers.values))
            return snapshot
        }
    }

    @discardableResult
    func navigate(by delta: Int) -> Bool {
        lock.withLock {
            guard !snapshot.slides.isEmpty else { return false }
            let (candidate, overflow) = snapshot.index.addingReportingOverflow(delta)
            let target = overflow
                ? (delta > 0 ? snapshot.slides.count - 1 : 0)
                : min(max(candidate, 0), snapshot.slides.count - 1)
            return navigateLocked(to: target)
        }
    }

    @discardableResult
    func navigate(to index: Int) -> Bool {
        lock.withLock {
            guard !snapshot.slides.isEmpty else { return false }
            let target = min(max(index, 0), snapshot.slides.count - 1)
            return navigateLocked(to: target)
        }
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

    private func navigateLocked(to index: Int) -> Bool {
        guard index != snapshot.index else { return false }
        snapshot = PresentationSnapshot(
            slides: snapshot.slides,
            index: index,
            version: snapshot.version + 1,
            deckVersion: snapshot.deckVersion,
            sourceURL: snapshot.sourceURL,
            workspaceRoot: snapshot.workspaceRoot,
            theme: snapshot.theme
        )
        enqueueNotification(snapshot, observers: Array(observers.values))
        return true
    }

    private func enqueueNotification(
        _ snapshot: PresentationSnapshot,
        observers: [Observer]
    ) {
        notificationQueue.async {
            observers.forEach { $0(snapshot) }
        }
    }
}
