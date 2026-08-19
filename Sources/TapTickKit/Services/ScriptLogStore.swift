import Foundation

/** Captured stdout/stderr and exit status for a single script run. */
struct ScriptExecutionResult: Sendable {
    let output: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detailText: String {
        if !trimmedOutput.isEmpty {
            return succeeded ? trimmedOutput : "\(trimmedOutput)\n\n[Exit code: \(exitCode)]"
        }

        return succeeded ? "(No output)" : "Script failed with exit code \(exitCode)"
    }

    private var overlaySource: String? {
        if !trimmedOutput.isEmpty {
            return trimmedOutput
        }

        return succeeded ? nil : "Script failed with exit code \(exitCode)"
    }

    func subtitleText(maxLines: Int = 6, maxLength: Int = 480) -> String? {
        guard let overlaySource else { return nil }

        let lines =
            overlaySource
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var result = Array(lines.suffix(maxLines)).joined(separator: "\n")

        guard !result.isEmpty else { return nil }

        if result.count > maxLength {
            result = "…" + String(result.suffix(maxLength - 1))
        }

        return result
    }
}

/// Record of a single script execution, stored for debugging.
public struct ScriptExecutionLog: Identifiable, Sendable {
    public let shortcutID: UUID
    public let output: String
    public let exitCode: Int32
    public let timestamp: Date

    public var id: String {
        "\(shortcutID.uuidString)-\(timestamp.timeIntervalSinceReferenceDate)"
    }

    public var succeeded: Bool { exitCode == 0 }

    public var displayText: String {
        result.detailText
    }

    public var subtitleText: String? {
        result.subtitleText()
    }

    var result: ScriptExecutionResult {
        ScriptExecutionResult(output: output, exitCode: exitCode)
    }
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
