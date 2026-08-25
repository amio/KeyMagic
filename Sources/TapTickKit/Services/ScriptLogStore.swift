import Foundation
import Observation

/** Captured stdout/stderr and exit status for a single script run. */
struct ScriptExecutionResult: Sendable {
    let output: String
    let exitCode: Int32
    let duration: TimeInterval

    init(output: String, exitCode: Int32, duration: TimeInterval = 0) {
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
    }

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
public struct ScriptExecutionLog: Codable, Identifiable, Sendable {
    public let shortcutID: UUID
    public let output: String
    public let exitCode: Int32
    public let duration: TimeInterval
    public let timestamp: Date

    public init(
        shortcutID: UUID,
        output: String,
        exitCode: Int32,
        timestamp: Date,
        duration: TimeInterval = 0
    ) {
        self.shortcutID = shortcutID
        self.output = output
        self.exitCode = exitCode
        self.timestamp = timestamp
        self.duration = duration
    }

    public var id: String {
        "\(shortcutID.uuidString)-\(timestamp.timeIntervalSinceReferenceDate)"
    }

    public var succeeded: Bool { exitCode == 0 }

    public var durationText: String {
        let safeDuration = max(0, duration)
        if safeDuration < 1 {
            let milliseconds = Int((safeDuration * 1_000).rounded())
            return milliseconds == 0 ? "<1 ms" : "\(milliseconds) ms"
        }

        if safeDuration < 60 {
            return "\(safeDuration.formatted(.number.precision(.fractionLength(0...2)))) sec"
        }

        let totalSeconds = Int(safeDuration.rounded(.down))
        return "\(totalSeconds / 60) min, \(totalSeconds % 60) sec"
    }

    public var displayText: String {
        result.detailText
    }

    public var subtitleText: String? {
        result.subtitleText()
    }

    var result: ScriptExecutionResult {
        ScriptExecutionResult(output: output, exitCode: exitCode, duration: duration)
    }
}

/// Owns the bounded, persisted execution history and the latest-log lookup used by the UI.
@Observable
@MainActor
public final class ScriptLogStore: @unchecked Sendable {
    public static let recentLogLimit = 12

    @ObservationIgnored private let fileURL: URL

    public init(directory: URL? = nil) {
        let baseDirectory =
            directory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent(
                TapTickRuntimeConfiguration.current.appSupportDirectoryName,
                isDirectory: true
            )

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        self.fileURL = baseDirectory.appendingPathComponent("script-logs.json")
        loadFromDisk()
    }

    public private(set) var logs: [UUID: ScriptExecutionLog] = [:]
    public private(set) var recentLogs: [ScriptExecutionLog] = []

    public func record(_ log: ScriptExecutionLog) {
        logs[log.shortcutID] = log
        recentLogs.removeAll { $0.id == log.id }
        recentLogs.insert(log, at: 0)
        trimHistory()
        saveToDisk()
    }

    public func recentLogs(for shortcutID: UUID) -> [ScriptExecutionLog] {
        recentLogs.filter { $0.shortcutID == shortcutID }
    }

    public func latestLog(for shortcutID: UUID) -> ScriptExecutionLog? {
        logs[shortcutID]
    }

    private func trimHistory() {
        guard recentLogs.count > Self.recentLogLimit else { return }
        recentLogs.removeLast(recentLogs.count - Self.recentLogLimit)
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let archive = try JSONDecoder().decode(ScriptLogArchive.self, from: data)
            recentLogs = Array(archive.logs.prefix(Self.recentLogLimit))

            for log in recentLogs.reversed() {
                logs[log.shortcutID] = log
            }
        } catch {
            print("TapTick: Failed to load script logs: \(error)")
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ScriptLogArchive(logs: recentLogs))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("TapTick: Failed to save script logs: \(error)")
        }
    }
}

private struct ScriptLogArchive: Codable, Sendable {
    let logs: [ScriptExecutionLog]
}
