import CoreServices
import Foundation

/// Observes one directory tree; the store intentionally reconciles only its first-level files.
final class ScriptDirectoryMonitor: @unchecked Sendable {
    private let onChange: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.taptick.script-directory-monitor")
    private var stream: FSEventStreamRef?

    init(directoryURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ScriptDirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.directoryDidChange()
        }
        let flags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)

        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                [directoryURL.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.2,
                flags
            )
        else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func directoryDidChange() {
        Task { @MainActor [onChange] in
            onChange()
        }
    }
}
