// Papyro/Services/FileSystemWatcher.swift
import Foundation
import CoreServices

enum FSEvent: Sendable {
    case pdfAdded(URL)
    case pdfRemoved(URL)
    case indexModified(URL)
    case rootChanged
}

/// Pure FSEvents wrapper. Watches one or more directories recursively,
/// debounces bursts, classifies events, and delivers them on a serial queue.
/// Knows nothing about Paper or any Papyro domain type.
final class FileSystemWatcher: @unchecked Sendable {
    private let directories: [URL]
    private let debounceMilliseconds: Int
    private let onEvent: @Sendable (FSEvent) -> Void

    private let queue = DispatchQueue(label: "papyro.fswatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingPaths: [(path: String, flags: FSEventStreamEventFlags)] = []

    init(
        directories: [URL],
        debounceMilliseconds: Int = 500,
        onEvent: @escaping @Sendable (FSEvent) -> Void
    ) {
        self.directories = directories
        self.debounceMilliseconds = debounceMilliseconds
        self.onEvent = onEvent
    }

    /// Returns true if the stream started. False means FSEvents failed to arm
    /// (caller should report and continue without live sync).
    @discardableResult
    func start() -> Bool {
        guard stream == nil else { return true }

        let paths = directories.map { $0.path } as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, flagsPtr, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: CFArray.self) as! [String]
            var raw: [(String, FSEventStreamEventFlags)] = []
            for i in 0..<count {
                raw.append((cfPaths[i], flagsPtr[i]))
            }
            watcher.enqueue(raw)
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,  // latency seconds
            flags
        ) else { return false }

        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            return false
        }
        stream = s
        return true
    }

    func stop() {
        queue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
            pendingPaths.removeAll()
        }
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    deinit { stop() }

    private func enqueue(_ raw: [(String, FSEventStreamEventFlags)]) {
        // Already on `queue` (set as dispatch queue for the stream).
        pendingPaths.append(contentsOf: raw)
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingWorkItem = work
        queue.asyncAfter(deadline: .now() + .milliseconds(debounceMilliseconds), execute: work)
    }

    private func flush() {
        let batch = pendingPaths
        pendingPaths.removeAll()
        pendingWorkItem = nil

        for (path, flags) in batch {
            // Root changed: tell the consumer and bail
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                onEvent(.rootChanged)
                continue
            }

            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()

            let isRemoved = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0
                && !FileManager.default.fileExists(atPath: path)

            if ext == "pdf" {
                if isRemoved {
                    onEvent(.pdfRemoved(url))
                } else if FileManager.default.fileExists(atPath: path) {
                    onEvent(.pdfAdded(url))
                }
            } else if ext == "json" && path.contains("/index/") {
                if !isRemoved && FileManager.default.fileExists(atPath: path) {
                    onEvent(.indexModified(url))
                }
            }
            // Everything else: ignore.
        }
    }
}
