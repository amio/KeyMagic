import Foundation

/// The deletion record used to keep removed shortcuts deleted across devices.
struct ShortcutDeletion: Codable, Equatable, Sendable {
    let id: UUID
    let deletedAt: Date
}

/// The complete persisted state used by local storage and iCloud sync.
struct ShortcutSyncState: Codable, Equatable, Sendable {
    var shortcuts: [Shortcut]
    var deletions: [ShortcutDeletion]

    static let empty = ShortcutSyncState(shortcuts: [], deletions: [])

    /// Decodes the current envelope or migrates the legacy shortcut-array format.
    static func decode(from data: Data, using decoder: JSONDecoder) throws -> ShortcutSyncState {
        do {
            return try decoder.decode(ShortcutSyncState.self, from: data)
        } catch {
            return ShortcutSyncState(
                shortcuts: try decoder.decode([Shortcut].self, from: data),
                deletions: []
            )
        }
    }
}
