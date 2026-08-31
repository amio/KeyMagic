import Testing
import Foundation
@testable import TapTickKit

@Suite("CloudSyncService")
struct CloudSyncServiceTests {

    private func makeShortcut(
        id: UUID = UUID(),
        name: String = "Test",
        modifiedAt: Date = Date()
    ) -> Shortcut {
        Shortcut(
            id: id,
            name: name,
            keyCombo: KeyCombo(keyCode: 0, modifiers: .command),
            action: .launchApp(bundleIdentifier: "com.test", appName: "Test"),
            modifiedAt: modifiedAt
        )
    }

    private func makeState(
        shortcuts: [Shortcut] = [],
        deletions: [ShortcutDeletion] = []
    ) -> ShortcutSyncState {
        ShortcutSyncState(shortcuts: shortcuts, deletions: deletions)
    }

    @Test("Merge: union of disjoint shortcuts")
    func mergeDisjoint() {
        let local = [makeShortcut(name: "Local")]
        let remote = [makeShortcut(name: "Remote")]
        let merged = CloudSyncService.merge(local: makeState(shortcuts: local), remote: makeState(shortcuts: remote))
        #expect(merged.shortcuts.count == 2)
        #expect(merged.shortcuts.contains { $0.name == "Local" })
        #expect(merged.shortcuts.contains { $0.name == "Remote" })
    }

    @Test("Merge: same ID — remote newer wins")
    func mergeRemoteNewer() {
        let id = UUID()
        let earlier = Date(timeIntervalSinceNow: -60)
        let later = Date()
        let local = [makeShortcut(id: id, name: "Old", modifiedAt: earlier)]
        let remote = [makeShortcut(id: id, name: "New", modifiedAt: later)]
        let merged = CloudSyncService.merge(local: makeState(shortcuts: local), remote: makeState(shortcuts: remote))
        #expect(merged.shortcuts.count == 1)
        #expect(merged.shortcuts.first?.name == "New")
    }

    @Test("Merge: same ID — local newer wins")
    func mergeLocalNewer() {
        let id = UUID()
        let earlier = Date(timeIntervalSinceNow: -60)
        let later = Date()
        let local = [makeShortcut(id: id, name: "Local", modifiedAt: later)]
        let remote = [makeShortcut(id: id, name: "Remote", modifiedAt: earlier)]
        let merged = CloudSyncService.merge(local: makeState(shortcuts: local), remote: makeState(shortcuts: remote))
        #expect(merged.shortcuts.count == 1)
        #expect(merged.shortcuts.first?.name == "Local")
    }

    @Test("Merge: empty local adopts all remote")
    func mergeEmptyLocal() {
        let remote = [makeShortcut(name: "A"), makeShortcut(name: "B")]
        let merged = CloudSyncService.merge(local: .empty, remote: makeState(shortcuts: remote))
        #expect(merged.shortcuts.count == 2)
    }

    @Test("Merge: empty remote keeps all local")
    func mergeEmptyRemote() {
        let local = [makeShortcut(name: "A"), makeShortcut(name: "B")]
        let merged = CloudSyncService.merge(local: makeState(shortcuts: local), remote: .empty)
        #expect(merged.shortcuts.count == 2)
    }

    @Test("Merge: both empty")
    func mergeBothEmpty() {
        let merged = CloudSyncService.merge(local: .empty, remote: .empty)
        #expect(merged == .empty)
    }

    @Test("Merge: result sorted by creation date")
    func mergeSortedByCreation() {
        let older = Date(timeIntervalSinceNow: -120)
        let newer = Date(timeIntervalSinceNow: -10)
        let s1 = Shortcut(name: "First", action: .runScript(script: "#!/bin/zsh\necho 1"), createdAt: older)
        let s2 = Shortcut(name: "Second", action: .runScript(script: "#!/bin/zsh\necho 2"), createdAt: newer)
        // Provide them in reverse order to prove sorting works.
        let merged = CloudSyncService.merge(
            local: makeState(shortcuts: [s2]),
            remote: makeState(shortcuts: [s1])
        )
        #expect(merged.shortcuts.count == 2)
        #expect(merged.shortcuts.first?.name == "First")
        #expect(merged.shortcuts.last?.name == "Second")
    }

    @Test("Merge: a newer deletion removes a stale shortcut")
    func mergeNewerDeletion() {
        let id = UUID()
        let shortcut = makeShortcut(id: id, modifiedAt: Date(timeIntervalSinceNow: -60))
        let deletion = ShortcutDeletion(id: id, deletedAt: Date())

        let merged = CloudSyncService.merge(
            local: makeState(shortcuts: [shortcut]),
            remote: makeState(deletions: [deletion])
        )

        #expect(merged.shortcuts.isEmpty)
        #expect(merged.deletions == [deletion])
    }

    @Test("Merge: a newer edit supersedes a stale deletion")
    func mergeNewerEdit() {
        let id = UUID()
        let deletion = ShortcutDeletion(id: id, deletedAt: Date(timeIntervalSinceNow: -60))
        let shortcut = makeShortcut(id: id, modifiedAt: Date())

        let merged = CloudSyncService.merge(
            local: makeState(deletions: [deletion]),
            remote: makeState(shortcuts: [shortcut])
        )

        #expect(merged.shortcuts == [shortcut])
        #expect(merged.deletions.isEmpty)
    }

    @Test("Merge: deletion wins an equal timestamp")
    func mergeEqualTimestampDeletion() {
        let id = UUID()
        let date = Date()
        let shortcut = makeShortcut(id: id, modifiedAt: date)
        let deletion = ShortcutDeletion(id: id, deletedAt: date)

        let merged = CloudSyncService.merge(
            local: makeState(shortcuts: [shortcut]),
            remote: makeState(deletions: [deletion])
        )

        #expect(merged.shortcuts.isEmpty)
        #expect(merged.deletions == [deletion])
    }

    @Test("Legacy shortcut arrays migrate to sync state without deletions")
    func legacyArrayMigration() throws {
        let shortcuts = [makeShortcut()]
        let data = try JSONEncoder().encode(shortcuts)

        let state = try ShortcutSyncState.decode(from: data, using: JSONDecoder())

        #expect(state.shortcuts == shortcuts)
        #expect(state.deletions.isEmpty)
    }

    @Test("Backward-compatible decoding: modifiedAt absent falls back to createdAt")
    func backwardCompatibleDecoding() throws {
        // Simulate a legacy JSON without the modifiedAt field.
        let json = """
            {
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "Legacy",
                "action": {"launchApp": {"bundleIdentifier": "com.test", "appName": "Test"}},
                "isEnabled": true,
                "createdAt": 700000000
            }
            """
        let data = Data(json.utf8)
        let shortcut = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(shortcut.name == "Legacy")
        #expect(shortcut.modifiedAt == shortcut.createdAt)
    }
}
