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
///
/// **Threading contract:**
/// - `start()` and `stop()` MUST be called from a single thread (in Papyro,
///   the main actor). Calling them concurrently is a programmer error.
/// - The `onEvent` callback runs on a private serial dispatch queue, NOT
///   the caller's thread. Hop to MainActor inside the callback if needed.
/// - Mutable internal state (`stream`, `pendingPaths`, `pendingWorkItem`) is
///   accessed only from the serial queue or from `start()`/`stop()` on the
///   single caller thread. `@unchecked Sendable` is sound under this contract.
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

        // FSEvents owns a strong reference to `self` for the stream's lifetime so
        // that in-flight callbacks cannot execute against a deallocated watcher.
        // Balanced by the release callback below (invoked by FSEventStreamRelease).
        let releaseCallback: CFAllocatorReleaseCallBack = { info in
            guard let info = info else { return }
            Unmanaged<FileSystemWatcher>.fromOpaque(info).release()
        }
        let unmanagedSelf = Unmanaged.passRetained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: unmanagedSelf.toOpaque(),
            retain: nil,
            release: releaseCallback,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, flagsPtr, _ in
            guard let info = info else { return }
            // Borrow — the +1 retain is owned by FSEvents via the context.
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
        ) else {
            // FSEvents never took ownership of the context — balance the retain manually.
            unmanagedSelf.release()
            return false
        }

        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)  // invokes context release callback, balancing the retain
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

            // Use on-disk existence as the source of truth rather than the
            // FSEvents flag bits. Finder's "Move to Trash" is a rename, not a
            // remove, so kFSEventStreamEventFlagItemRemoved is not set — but
            // the file is gone from the watched directory all the same.
            let exists = FileManager.default.fileExists(atPath: path)

            if ext == "pdf" {
                if exists {
                    onEvent(.pdfAdded(url))
                } else {
                    onEvent(.pdfRemoved(url))
                }
            } else if ext == "json" && path.contains("/index/") {
                if exists {
                    onEvent(.indexModified(url))
                }
            }
            // Everything else: ignore.
        }
    }
}
