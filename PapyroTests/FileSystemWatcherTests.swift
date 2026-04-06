import Testing
import Foundation
@testable import Papyro

struct FileSystemWatcherTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PapyroFSW-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func emitsPDFAddedAfterDebounce() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let received = Mutex<[FSEvent]>([])
        let watcher = FileSystemWatcher(
            directories: [dir],
            debounceMilliseconds: 200
        ) { event in
            received.withLock { $0.append(event) }
        }
        watcher.start()
        defer { watcher.stop() }

        // Give FSEvents time to arm
        try await Task.sleep(nanoseconds: 200_000_000)

        let pdfURL = dir.appendingPathComponent("a.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        // Wait for debounce + delivery
        try await Task.sleep(nanoseconds: 800_000_000)

        let events = received.withLock { $0 }
        #expect(events.contains { event in
            if case .pdfAdded(let url) = event { return url.lastPathComponent == "a.pdf" }
            return false
        })
    }

    @Test func emitsPDFRemoved() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pdfURL = dir.appendingPathComponent("doomed.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        let received = Mutex<[FSEvent]>([])
        let watcher = FileSystemWatcher(
            directories: [dir],
            debounceMilliseconds: 200
        ) { event in
            received.withLock { $0.append(event) }
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        try FileManager.default.removeItem(at: pdfURL)
        try await Task.sleep(nanoseconds: 800_000_000)

        let events = received.withLock { $0 }
        #expect(events.contains { event in
            if case .pdfRemoved(let url) = event { return url.lastPathComponent == "doomed.pdf" }
            return false
        })
    }

    @Test func ignoresNonPDFNonJSONFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let received = Mutex<[FSEvent]>([])
        let watcher = FileSystemWatcher(
            directories: [dir],
            debounceMilliseconds: 200
        ) { event in
            received.withLock { $0.append(event) }
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        // Create both a .txt (should be ignored) and a .pdf (should be delivered).
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("notes.txt").path,
            contents: Data())
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("paper.pdf").path,
            contents: Data())
        try await Task.sleep(nanoseconds: 800_000_000)

        let events = received.withLock { $0 }
        // Must contain the PDF event — proves delivery works.
        #expect(events.contains { event in
            if case .pdfAdded(let url) = event { return url.lastPathComponent == "paper.pdf" }
            return false
        })
        // Must NOT contain anything mentioning notes.txt.
        #expect(!events.contains { event in
            switch event {
            case .pdfAdded(let url), .pdfRemoved(let url), .indexModified(let url):
                return url.lastPathComponent == "notes.txt"
            case .rootChanged:
                return false
            }
        })
    }
}

/// Tiny mutex helper for collecting events from the watcher's serial queue.
private final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
