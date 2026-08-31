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
