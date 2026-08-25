import Foundation
import Testing
@testable import TapTickKit

@Suite("ScriptRunner")
struct ScriptRunnerTests {
    @Test("Captures combined output and nonzero exit status")
    func capturesOutputAndExitStatus() async {
        let result = await ScriptRunner.live.run(
            .inline(
                script: "printf output; printf error >&2; exit 7",
                shell: .sh
            )
        )

        #expect(result.output == "outputerror")
        #expect(result.exitCode == 7)
        #expect(!result.succeeded)
        #expect(result.duration > 0)
    }

    @Test("Reports a missing script file as a typed process failure")
    func reportsMissingFile() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTick-missing-\(UUID().uuidString).sh")
            .path

        let result = await ScriptRunner.live.run(.file(path: path, shell: .sh))

        guard case .failed(let message) = result.termination else {
            Issue.record("Expected a failed termination")
            return
        }
        #expect(message.contains("Script file not found"))
        #expect(result.exitCode == -1)
    }

    @Test("Drains output while the child process is running")
    func drainsLargeOutput() async {
        let byteCount = 262_144
        let result = await ScriptRunner.live.run(
            .inline(
                script: "/usr/bin/yes x | /usr/bin/head -c \(byteCount)",
                shell: .sh
            )
        )

        #expect(result.succeeded)
        #expect(result.output.utf8.count == byteCount)
    }
}
