import Foundation
import Testing
@testable import TapTickKit

@Suite("ScriptRunner")
struct ScriptRunnerTests {
    @Test("Captures combined output and nonzero exit status")
    func capturesOutputAndExitStatus() async throws {
        let url = try makeScript("#!/bin/sh\nprintf output; printf error >&2; exit 7")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = await ScriptRunner.live.run(ScriptCommand(fileURL: url))

        #expect(result.output == "outputerror")
        #expect(result.exitCode == 7)
        #expect(!result.succeeded)
        #expect(result.duration > 0)
    }

    @Test("Reports a missing script file as a typed process failure")
    func reportsMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTick-missing-\(UUID().uuidString)")

        let result = await ScriptRunner.live.run(ScriptCommand(fileURL: url))

        guard case .failed(let message) = result.termination else {
            Issue.record("Expected a failed termination")
            return
        }
        #expect(message.contains("Script file not found"))
        #expect(result.exitCode == -1)
    }

    @Test("Rejects a script without a shebang")
    func rejectsMissingShebang() async throws {
        let url = try makeScript("echo no")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = await ScriptRunner.live.run(ScriptCommand(fileURL: url))

        #expect(!result.succeeded)
        #expect(result.output.contains("shebang"))
    }

    @Test("Drains output while the child process is running")
    func drainsLargeOutput() async throws {
        let byteCount = 262_144
        let url = try makeScript(
            "#!/bin/sh\n/usr/bin/yes x | /usr/bin/head -c \(byteCount)"
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = await ScriptRunner.live.run(ScriptCommand(fileURL: url))

        #expect(result.succeeded)
        #expect(result.output.utf8.count == byteCount)
    }

    @Test("Timeout stops scripts that ignore TERM and preserves partial output")
    func timesOutUnresponsiveScript() async throws {
        let url = try makeScript("#!/bin/sh\ntrap '' TERM\nprintf partial\nwhile :; do :; done")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = await ScriptRunner.process(timeout: 2).run(ScriptCommand(fileURL: url))

        #expect(!result.succeeded)
        #expect(result.output.contains("partial"))
        #expect(result.output.contains("timed out"))
        #expect(result.duration < 5)
        let log = ScriptExecutionLog(shortcutID: UUID(), result: result)
        let restored = try JSONDecoder().decode(ScriptExecutionLog.self, from: JSONEncoder().encode(log))
        #expect(restored.displayText.contains("timed out"))
        #expect(restored.subtitleText?.contains("timed out") == true)
    }

    @Test("Timeout also covers inherited pipes after the script exits")
    func timesOutInheritedPipe() async throws {
        let url = try makeScript("#!/bin/sh\n/bin/sleep 30 &\nprintf started\nexit 0")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = await ScriptRunner.process(timeout: 2).run(ScriptCommand(fileURL: url))

        #expect(!result.succeeded)
        #expect(result.output.contains("started"))
        #expect(result.output.contains("timed out"))
        #expect(result.duration < 5)
    }

    private func makeScript(_ source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("script")
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: url.path
        )
        return url
    }
}
