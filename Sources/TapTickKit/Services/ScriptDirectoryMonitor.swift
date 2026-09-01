import CoreServices
import Foundation

private final class ScriptDirectoryMonitorCallbackContext: @unchecked Sendable {
    private let onChange: @MainActor @Sendable () -> Void

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    func directoryDidChange() {
        Task { @MainActor [onChange] in
            onChange()
        }
    }
}

/// Observes one directory tree; the store intentionally reconciles only its first-level files.
final class ScriptDirectoryMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.taptick.script-directory-monitor")
    private var stream: FSEventStreamRef?

    init(directoryURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        let callbackContext = ScriptDirectoryMonitorCallbackContext(onChange: onChange)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackContext).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<ScriptDirectoryMonitorCallbackContext>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<ScriptDirectoryMonitorCallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let context = Unmanaged<ScriptDirectoryMonitorCallbackContext>
                .fromOpaque(info)
                .takeUnretainedValue()
            context.directoryDidChange()
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
}
