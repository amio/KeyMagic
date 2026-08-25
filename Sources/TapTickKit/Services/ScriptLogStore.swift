import Foundation
import Observation

/// Record of a single script execution, stored for debugging.
public struct ScriptExecutionLog: Codable, Identifiable, Sendable {
    public let shortcutID: UUID
    public let timestamp: Date
    let result: ScriptExecutionResult

    public var output: String { result.output }
    public var exitCode: Int32 { result.exitCode }
    public var duration: TimeInterval { result.duration }

    public init(
        shortcutID: UUID,
        output: String,
        exitCode: Int32,
        timestamp: Date,
        duration: TimeInterval = 0
    ) {
        self.shortcutID = shortcutID
        self.timestamp = timestamp
        self.result = ScriptExecutionResult(
            output: output,
            exitCode: exitCode,
            startedAt: timestamp,
            duration: duration
        )
    }

    init(shortcutID: UUID, result: ScriptExecutionResult) {
        self.shortcutID = shortcutID
        self.timestamp = result.startedAt
        self.result = result
    }

    public var id: String {
        "\(shortcutID.uuidString)-\(timestamp.timeIntervalSinceReferenceDate)"
    }

    public var succeeded: Bool { result.succeeded }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortcutID = try container.decode(UUID.self, forKey: .shortcutID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        result = ScriptExecutionResult(
            output: try container.decode(String.self, forKey: .output),
            exitCode: try container.decode(Int32.self, forKey: .exitCode),
            startedAt: timestamp,
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shortcutID, forKey: .shortcutID)
        try container.encode(output, forKey: .output)
        try container.encode(exitCode, forKey: .exitCode)
        try container.encode(duration, forKey: .duration)
        try container.encode(timestamp, forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case shortcutID
        case output
        case exitCode
        case duration
        case timestamp
    }
}

/// Owns the bounded, persisted execution history used by the UI.
@Observable
@MainActor
public final class ScriptLogStore: @unchecked Sendable {
    /// Maximum persisted executions retained independently for each script.
    public static let recentLogLimit = 32

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

    public private(set) var recentLogs: [ScriptExecutionLog] = []

    public func record(_ log: ScriptExecutionLog) {
        recentLogs.removeAll { $0.id == log.id }
        recentLogs.insert(log, at: 0)
        trimHistory()
        saveToDisk()
    }

    public func recentLogs(for shortcutID: UUID) -> [ScriptExecutionLog] {
        recentLogs.filter { $0.shortcutID == shortcutID }
    }

    private func trimHistory() {
        var retainedCountByShortcut: [UUID: Int] = [:]
        recentLogs.removeAll { log in
            let retainedCount = retainedCountByShortcut[log.shortcutID, default: 0]
            guard retainedCount >= Self.recentLogLimit else {
                retainedCountByShortcut[log.shortcutID] = retainedCount + 1
                return false
            }
            return true
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let archive = try JSONDecoder().decode(ScriptLogArchive.self, from: data)
            recentLogs = archive.logs
            trimHistory()
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
