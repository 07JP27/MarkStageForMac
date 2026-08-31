import Foundation
import XCTest
@testable import MarkdStage

@MainActor
final class DeckWatcherTests: XCTestCase {
    func testDetectsInPlaceSave() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let watcher = DeckWatcher()
        defer { watcher.stop() }
        let changed = expectation(description: "In-place save detected")
        var fulfilled = false
        try watcher.start(fileURL: fixture.file) {
            guard !fulfilled else { return }
            fulfilled = true
            changed.fulfill()
        }

        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: fixture.file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("# Updated in place".utf8))
        try handle.close()

        await fulfillment(of: [changed], timeout: 3)
    }

    func testDetectsAtomicReplacementAndKeepsWatching() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let watcher = DeckWatcher()
        defer { watcher.stop() }
        let changed = expectation(description: "Atomic saves detected")
        changed.expectedFulfillmentCount = 2
        var count = 0
        try watcher.start(fileURL: fixture.file) {
            count += 1
            if count <= 2 {
                changed.fulfill()
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        try Data("# First atomic save".utf8).write(to: fixture.file, options: .atomic)
        try await Task.sleep(for: .milliseconds(500))
        try Data("# Second atomic save".utf8).write(to: fixture.file, options: .atomic)

        await fulfillment(of: [changed], timeout: 4)
    }

    func testReadingDoesNotTriggerChange() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let watcher = DeckWatcher()
        defer { watcher.stop() }
        let changed = expectation(description: "Read is ignored")
        changed.isInverted = true
        try watcher.start(fileURL: fixture.file) {
            changed.fulfill()
        }

        try await Task.sleep(for: .milliseconds(100))
        _ = try Data(contentsOf: fixture.file)

        await fulfillment(of: [changed], timeout: 0.6)
    }

    private func makeFixture() throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdStageWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("deck.md")
        try "# Initial".write(to: file, atomically: true, encoding: .utf8)
        return (root, file)
    }
}
