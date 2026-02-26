import Foundation

/// A single user-defined shortcut binding a key combo to an action.
struct Shortcut: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The key combination that triggers this shortcut. `nil` means no hotkey is bound yet.
    var keyCombo: KeyCombo?
    var action: ShortcutAction
    var isEnabled: Bool
    var createdAt: Date
    var lastTriggeredAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        keyCombo: KeyCombo? = nil,
        action: ShortcutAction,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.keyCombo = keyCombo
        self.action = action
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastTriggeredAt = lastTriggeredAt
    }
}
