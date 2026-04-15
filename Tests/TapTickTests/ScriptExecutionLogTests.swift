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
}
