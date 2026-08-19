import Foundation
import Observation
import os.log

/// Manages bidirectional iCloud Drive sync for shortcut data.
///
/// Uses the iCloud ubiquity container (`iCloud.com.taptick.app`) to store a shared
/// `shortcuts.json` file. Monitors the file for external changes pushed from other
/// devices via `NSMetadataQuery` and merges them into the local store.
///
/// Merge strategy: the newest edit or deletion wins for each UUID. Deletion records
/// remain in the sync state so a stale device cannot resurrect a removed shortcut.
@MainActor
@Observable
public final class CloudSyncService {
    // MARK: - State

    private(set) var isSyncing = false
    private(set) var isAvailable = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    /// User preference — stored separately so it survives even when iCloud is unavailable.
    @ObservationIgnored
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue { startMonitoring() } else { stopMonitoring() }
        }
    }

    // MARK: - Dependencies

    /// Callback invoked when remote changes are detected. The ShortcutStore sets this.
    var onRemoteChange: ((ShortcutSyncState) -> Void)?

    // MARK: - Private

    private static let enabledKey = "iCloudSyncEnabled"
    private static let containerID = "iCloud.com.taptick.app"
    private static let fileName = "shortcuts.json"

    private let logger = Logger(
        subsystem: TapTickRuntimeConfiguration.current.bundleIdentifier,
        category: "CloudSync"
    )
    private var metadataQuery: NSMetadataQuery?
    private var containerURL: URL?
    @ObservationIgnored private let notificationObservers = NotificationObserverBag()

    // Debounce remote-change processing to avoid thrashing during bulk syncs.
    private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(500)

    public init() {
        checkAvailability()
        if isEnabled && isAvailable {
            startMonitoring()
        }
    }

    // MARK: - iCloud Container

    /// Resolve the ubiquity container URL. Returns nil when iCloud is not signed in.
    private func checkAvailability() {
        // url(forUbiquityContainerIdentifier:) returns nil when iCloud is off or unavailable.
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) {
            containerURL = url.appendingPathComponent("Documents", isDirectory: true)
            isAvailable = true

            // Ensure the Documents subdirectory exists.
            try? FileManager.default.createDirectory(
                at: containerURL!, withIntermediateDirectories: true
            )
        } else {
            containerURL = nil
            isAvailable = false
        }
    }

    /// Full path to the synced file inside the iCloud container.
    private var cloudFileURL: URL? {
        containerURL?.appendingPathComponent(Self.fileName)
    }

    // MARK: - Monitoring

    /// Begin watching the iCloud file for external changes.
    /// Must be called on the main thread (NSMetadataQuery requires it).
    func startMonitoring() {
        guard isAvailable, metadataQuery == nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, Self.fileName)

        notificationObservers.insert(
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMetadataQueryUpdate()
                }
            })

        notificationObservers.insert(
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMetadataQueryUpdate()
                }
            })

        query.start()
        metadataQuery = query
        logger.info("Started iCloud monitoring")
    }

    /// Stop watching.
    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        debounceTask?.cancel()
        debounceTask = nil
        notificationObservers.removeAll()
        logger.info("Stopped iCloud monitoring")
    }

    // MARK: - Upload

    /// Write the current local sync state to the iCloud container.
    func upload(_ state: ShortcutSyncState) {
        guard isEnabled, isAvailable, let url = cloudFileURL else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)

            // Use file coordination to avoid conflicts with iCloud daemon.
            var error: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
                do {
                    try data.write(to: coordURL, options: .atomic)
                    self.lastSyncDate = Date()
                    self.lastError = nil
                    self.logger.info(
                        "Uploaded \(state.shortcuts.count) shortcuts and \(state.deletions.count) deletions to iCloud"
                    )
                } catch {
                    self.lastError = error.localizedDescription
                    self.logger.error("Upload write failed: \(error)")
                }
            }

            if let error {
                lastError = error.localizedDescription
                logger.error("Upload coordination failed: \(error)")
            }
        } catch {
            lastError = error.localizedDescription
            logger.error("Upload encode failed: \(error)")
        }
    }

    /// Read sync state from iCloud. Returns nil if no cloud file exists.
    func download() -> ShortcutSyncState? {
        guard isEnabled, isAvailable, let url = cloudFileURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var result: ShortcutSyncState?
        var coordError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordURL in
            do {
                let data = try Data(contentsOf: coordURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                result = try ShortcutSyncState.decode(from: data, using: decoder)
            } catch {
                self.lastError = error.localizedDescription
                self.logger.error("Download failed: \(error)")
            }
        }

        if let coordError {
            lastError = coordError.localizedDescription
            logger.error("Download coordination failed: \(coordError)")
        }

        return result
    }

    // MARK: - Merge

    /// Merge local and remote state using the newest event for each shortcut ID.
    ///
    /// Rules:
    /// - The later `modifiedAt` wins between live shortcuts with the same ID.
    /// - The later `deletedAt` wins between deletion records with the same ID.
    /// - A deletion wins when its timestamp is equal to or later than the live edit.
    nonisolated static func merge(local: ShortcutSyncState, remote: ShortcutSyncState) -> ShortcutSyncState {
        var shortcutsByID: [UUID: Shortcut] = [:]
        var deletionsByID: [UUID: ShortcutDeletion] = [:]

        for shortcut in local.shortcuts + remote.shortcuts {
            if let existing = shortcutsByID[shortcut.id], existing.modifiedAt >= shortcut.modifiedAt {
                continue
            }
            shortcutsByID[shortcut.id] = shortcut
        }

        for deletion in local.deletions + remote.deletions {
            if let existing = deletionsByID[deletion.id], existing.deletedAt >= deletion.deletedAt {
                continue
            }
            deletionsByID[deletion.id] = deletion
        }

        for (id, deletion) in deletionsByID {
            guard let shortcut = shortcutsByID[id] else { continue }
            if shortcut.modifiedAt > deletion.deletedAt {
                deletionsByID[id] = nil
            } else {
                shortcutsByID[id] = nil
            }
        }

        return ShortcutSyncState(
            shortcuts: shortcutsByID.values.sorted { $0.createdAt < $1.createdAt },
            deletions: deletionsByID.values.sorted {
                if $0.deletedAt == $1.deletedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.deletedAt < $1.deletedAt
            }
        )
    }

    // MARK: - Internal

    /// Called when the metadata query detects a change to the cloud file.
    private func handleMetadataQueryUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            self?.processRemoteChange()
        }
    }

    private func processRemoteChange() {
        guard let remoteState = download() else { return }
        logger.info(
            "Remote change detected: \(remoteState.shortcuts.count) shortcuts and \(remoteState.deletions.count) deletions"
        )
        lastSyncDate = Date()
        onRemoteChange?(remoteState)
    }
}

/// Owns block-based notification tokens so teardown remains exact even during deinitialization.
private final class NotificationObserverBag: @unchecked Sendable {
    private var observers: [NSObjectProtocol] = []

    func insert(_ observer: NSObjectProtocol) {
        observers.append(observer)
    }

    func removeAll() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        removeAll()
    }
}
