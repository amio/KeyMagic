import Foundation
import Observation

/// Manages persistence and in-memory state of all user-defined shortcuts.
///
/// Local data lives in a variant-specific Application Support directory
/// (`TapTick` for release, `TapTick Dev` for Debug).
/// When iCloud sync is enabled, every local mutation is also pushed to the cloud,
/// and remote changes are merged in automatically via `CloudSyncService`.
@MainActor
@Observable
public final class ShortcutStore {
    // MARK: - Published State

    private(set) var shortcuts: [Shortcut] = []
    @ObservationIgnored private(set) var deletions: [ShortcutDeletion] = []

    // MARK: - Persistence

    private let fileURL: URL
    private let cloudSync: CloudSyncService?

    public init(directory: URL? = nil, cloudSync: CloudSyncService? = nil) {
        let dir =
            directory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(
                TapTickRuntimeConfiguration.current.appSupportDirectoryName,
                isDirectory: true
            )

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("shortcuts.json")
        self.cloudSync = cloudSync
        loadFromDisk()
        setupCloudSync()
    }

    /// Wire up the cloud sync callback so remote changes are merged automatically.
    private func setupCloudSync() {
        guard let cloudSync else { return }
        cloudSync.onRemoteChange = { [weak self] remoteState in
            self?.applyRemoteChanges(remoteState)
        }
    }

    // MARK: - CRUD Operations

    func add(_ shortcut: Shortcut) {
        var s = shortcut
        s.modifiedAt = Date()
        clearDeletion(for: s.id)
        shortcuts.append(s)
        saveToDisk()
        syncToCloud()
    }

    func update(_ shortcut: Shortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        var s = shortcut
        s.modifiedAt = Date()
        clearDeletion(for: s.id)
        shortcuts[index] = s
        saveToDisk()
        syncToCloud()
    }

    /// Persist fields owned by the script editor.
    /// Unrelated fields come from the latest store value so autosave cannot overwrite a hotkey edit.
    func updateScript(_ shortcut: Shortcut) {
        guard let current = shortcuts.first(where: { $0.id == shortcut.id }) else { return }
        guard !current.action.isLaunchApp, !shortcut.action.isLaunchApp else { return }
        guard current.name != shortcut.name || current.action != shortcut.action else { return }

        var updated = current
        updated.name = shortcut.name
        updated.action = shortcut.action
        update(updated)
    }

    func remove(id: UUID) {
        guard shortcuts.contains(where: { $0.id == id }) else { return }
        shortcuts.removeAll { $0.id == id }
        recordDeletion(id: id, at: Date())
        saveToDisk()
        syncToCloud()
    }

    func remove(atOffsets offsets: IndexSet) {
        let ids = offsets.map { shortcuts[$0].id }
        shortcuts.remove(atOffsets: offsets)
        let deletionDate = Date()
        for id in ids {
            recordDeletion(id: id, at: deletionDate)
        }
        saveToDisk()
        syncToCloud()
    }

    func toggleEnabled(id: UUID) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index].isEnabled.toggle()
        shortcuts[index].modifiedAt = Date()
        saveToDisk()
        syncToCloud()
    }

    func markTriggered(id: UUID) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index].lastTriggeredAt = Date()
        // Trigger timestamps are local-only — no cloud sync or modifiedAt bump.
        saveToDisk()
    }

    func shortcut(for keyCombo: KeyCombo) -> Shortcut? {
        shortcuts.first { $0.keyCombo == keyCombo && $0.isEnabled }
    }

    func hasConflict(keyCombo: KeyCombo, excludingID: UUID? = nil) -> Bool {
        shortcuts.contains { shortcut in
            // Shortcuts with no bound hotkey never conflict.
            guard let bound = shortcut.keyCombo else { return false }
            return bound == keyCombo && shortcut.id != excludingID
        }
    }

    // MARK: - Cloud Sync

    private func syncToCloud() {
        cloudSync?.upload(syncState)
    }

    /// Merge remote state locally and publish the result when the remote side was stale.
    private func applyRemoteChanges(_ remoteState: ShortcutSyncState) {
        let merged = CloudSyncService.merge(local: syncState, remote: remoteState)

        if merged != syncState {
            apply(merged)
            saveToDisk()
        }

        if merged != remoteState {
            cloudSync?.upload(merged)
        }
    }

    /// Perform a full sync: download + merge + upload the merged result.
    func performFullSync() {
        guard let cloudSync, cloudSync.isEnabled else { return }

        if let remote = cloudSync.download() {
            let merged = CloudSyncService.merge(local: syncState, remote: remote)
            apply(merged)
            saveToDisk()
        }

        // Upload the (possibly merged) local data so the cloud has the latest.
        cloudSync.upload(syncState)
    }

    // MARK: - Disk I/O

    func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            apply(.empty)
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            apply(try ShortcutSyncState.decode(from: data, using: JSONDecoder()))
        } catch {
            print("TapTick: Failed to load shortcuts: \(error)")
            apply(.empty)
        }
    }

    func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(syncState)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("TapTick: Failed to save shortcuts: \(error)")
        }
    }

    // MARK: - Import/Export

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(shortcuts)
    }

    func importData(_ data: Data) throws {
        let importDate = Date()
        shortcuts = try JSONDecoder().decode([Shortcut].self, from: data).map { shortcut in
            var restored = shortcut
            restored.modifiedAt = importDate
            return restored
        }
        deletions = []
        saveToDisk()
        syncToCloud()
    }

    // MARK: - Sync State

    private var syncState: ShortcutSyncState {
        ShortcutSyncState(shortcuts: shortcuts, deletions: deletions)
    }

    private func apply(_ state: ShortcutSyncState) {
        shortcuts = state.shortcuts
        deletions = state.deletions
    }

    private func recordDeletion(id: UUID, at date: Date) {
        deletions.removeAll { $0.id == id }
        deletions.append(ShortcutDeletion(id: id, deletedAt: date))
    }

    private func clearDeletion(for id: UUID) {
        deletions.removeAll { $0.id == id }
    }
}
