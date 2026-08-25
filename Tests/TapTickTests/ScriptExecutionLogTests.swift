import Foundation
import Testing
@testable import TapTickKit

@Suite("ScriptExecutionLog")
struct ScriptExecutionLogTests {
    @Test("Successful logs keep full output for the detail viewer")
    func detailTextPreservesSuccessfulOutput() {
        let log = ScriptExecutionLog(
            shortcutID: UUID(),
            output: "line 1\nline 2\n",
            exitCode: 0,
            timestamp: Date()
        )

        #expect(log.displayText == "line 1\nline 2")
    }

    @Test("Failed logs append the exit code in the detail viewer")
    func detailTextShowsExitCodeForFailures() {
        let log = ScriptExecutionLog(
            shortcutID: UUID(),
            output: "fatal: missing token\n",
            exitCode: 9,
            timestamp: Date()
        )

        #expect(log.displayText == "fatal: missing token\n\n[Exit code: 9]")
    }

    @Test("Subtitle preview shows the latest lines without dropping the underlying full log")
    func subtitlePreviewUsesTailLines() {
        let log = ScriptExecutionLog(
            shortcutID: UUID(),
            output: """
                line 1
                line 2
                line 3
                line 4
                line 5
                line 6
                line 7
                """,
            exitCode: 0,
            timestamp: Date()
        )

        #expect(log.subtitleText == "line 2\nline 3\nline 4\nline 5\nline 6\nline 7")
        #expect(log.displayText == "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7")
    }

    @Test("Empty successful output stays silent in the subtitle but readable in the sheet")
    func emptySuccessfulOutputHasSheetFallbackOnly() {
        let log = ScriptExecutionLog(
            shortcutID: UUID(),
            output: "\n",
            exitCode: 0,
            timestamp: Date()
        )

        #expect(log.subtitleText == nil)
        #expect(log.displayText == "(No output)")
    }

    @Test("Execution logs format the measured duration for review")
    func durationTextUsesReadableUnits() {
        let shortcutID = UUID()

        let milliseconds = ScriptExecutionLog(
            shortcutID: shortcutID,
            output: "",
            exitCode: 0,
            timestamp: Date(),
            duration: 0.125
        )
        let seconds = ScriptExecutionLog(
            shortcutID: shortcutID,
            output: "",
            exitCode: 0,
            timestamp: Date(),
            duration: 1.25
        )
        let minutes = ScriptExecutionLog(
            shortcutID: shortcutID,
            output: "",
            exitCode: 0,
            timestamp: Date(),
            duration: 125
        )

        #expect(milliseconds.durationText == "125 ms")
        #expect(seconds.durationText == "1.25 sec")
        #expect(minutes.durationText == "2 min, 5 sec")
    }

    @Test("Log store keeps the 12 most recent executions in completion order")
    @MainActor
    func logStoreKeepsRecentHistory() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ScriptLogStore(directory: directory)
        let shortcutID = UUID()
        let logs = (0..<14).map { index in
            ScriptExecutionLog(
                shortcutID: shortcutID,
                output: "run \(index)",
                exitCode: 0,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        for log in logs {
            store.record(log)
        }

        #expect(store.recentLogs.count == ScriptLogStore.recentLogLimit)
        #expect(store.recentLogs.map(\.output) == (2..<14).reversed().map { "run \($0)" })
        #expect(store.latestLog(for: shortcutID)?.output == "run 13")
    }

    @Test("Log store keeps repeated executions while exposing the latest per shortcut")
    @MainActor
    func logStoreKeepsRepeatedExecutions() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ScriptLogStore(directory: directory)
        let shortcutID = UUID()
        let first = ScriptExecutionLog(
            shortcutID: shortcutID,
            output: "first",
            exitCode: 0,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = ScriptExecutionLog(
            shortcutID: shortcutID,
            output: "second",
            exitCode: 1,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        store.record(first)
        store.record(second)

        #expect(store.recentLogs.map(\.output) == ["second", "first"])
        #expect(store.logs.count == 1)
        #expect(store.latestLog(for: shortcutID)?.output == "second")
    }

    @Test("Log store persists history and filters it by shortcut")
    @MainActor
    func logStorePersistsAndFiltersHistory() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentShortcutID = UUID()
        let otherShortcutID = UUID()
        let currentLog = ScriptExecutionLog(
            shortcutID: currentShortcutID,
            output: "current",
            exitCode: 0,
            timestamp: Date(timeIntervalSince1970: 10),
            duration: 0.25
        )
        let otherLog = ScriptExecutionLog(
            shortcutID: otherShortcutID,
            output: "other",
            exitCode: 0,
            timestamp: Date(timeIntervalSince1970: 9),
            duration: 0.5
        )

        let store = ScriptLogStore(directory: directory)
        store.record(otherLog)
        store.record(currentLog)

        let reloadedStore = ScriptLogStore(directory: directory)
        #expect(reloadedStore.recentLogs.map(\.output) == ["current", "other"])
        #expect(reloadedStore.recentLogs(for: currentShortcutID).map(\.output) == ["current"])
        #expect(reloadedStore.latestLog(for: currentShortcutID)?.duration == 0.25)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickScriptLogs-\(UUID().uuidString)")
    }
}
