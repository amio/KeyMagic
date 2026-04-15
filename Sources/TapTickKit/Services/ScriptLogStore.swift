import Foundation

/// Record of a single script execution, stored for debugging.
public struct ScriptExecutionLog: Sendable {
    public let shortcutID: UUID
    public let output: String
    public let exitCode: Int32
    public let timestamp: Date

    public var succeeded: Bool { exitCode == 0 }
}

/// Keeps the most recent script execution log per shortcut (in-memory only).
@Observable
@MainActor
public final class ScriptLogStore: @unchecked Sendable {
    public init() {}

    public private(set) var logs: [UUID: ScriptExecutionLog] = [:]

    public func record(_ log: ScriptExecutionLog) {
        logs[log.shortcutID] = log
    }
}