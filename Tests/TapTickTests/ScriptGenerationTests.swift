import Darwin
import Foundation
import Testing
@testable import TapTickKit

@Suite("Script generation protocols")
struct ScriptGenerationOutputTests {
    private let script = "#!/bin/sh\nprintf '你好\\n'\n"

    @Test(
        "CLI protocols keep only assistant code and reconcile streamed final text",
        arguments: [
            ScriptGenerationProvider.codex, .claude, .gemini, .copilot, .grok, .opencode,
        ])
    func providerStreams(_ provider: ScriptGenerationProvider) throws {
        var decoder = ScriptGenerationOutput(provider: provider)
        let events: [[String: Any]]
        switch provider {
        case .codex:
            events = [
                ["type": "item.completed", "item": ["type": "reasoning", "text": "thinking"]],
                ["type": "item.completed", "item": ["type": "command_execution", "text": "diagnostic"]],
                ["type": "item.completed", "item": ["type": "agent_message", "text": script]],
                ["type": "turn.completed"],
            ]
        case .claude, .grok:
            events = [
                ["type": "stream_event", "event": ["type": "message_start"]],
                [
                    "type": "stream_event",
                    "event": [
                        "type": "content_block_delta", "delta": ["type": "thinking_delta", "thinking": "hidden"],
                    ],
                ],
                [
                    "type": "stream_event",
                    "event": [
                        "type": "content_block_delta", "delta": ["type": "text_delta", "text": script],
                    ],
                ],
                ["type": "assistant", "message": ["content": [["type": "text", "text": script]]]],
                ["type": "result", "subtype": "success", "result": script, "is_error": false],
            ]
        case .gemini:
            events = [
                ["type": "message", "role": "user", "content": "request"],
                ["type": "message", "role": "assistant", "content": "#!/bin/sh\n", "delta": true],
                ["type": "message", "role": "assistant", "content": "printf '你好\\n'\n", "delta": true],
                ["type": "result", "status": "success"],
            ]
        case .copilot:
            events = [
                ["type": "assistant.message_start", "data": ["messageId": "message"]],
                ["type": "assistant.message_delta", "data": ["deltaContent": script]],
                ["type": "assistant.reasoning_delta", "data": ["deltaContent": "hidden"]],
                ["type": "assistant.message_delta", "data": ["parentToolCallId": "child", "deltaContent": "child"]],
                ["type": "assistant.message", "data": ["content": script]],
                ["type": "session.idle"],
            ]
        case .opencode:
            events = [
                ["type": "text", "part": ["id": "a", "text": "#!/bin/sh\n"]],
                ["type": "text", "part": ["id": "a", "text": "#!/bin/sh\n"]],
                ["type": "text", "part": ["id": "b", "text": "printf '你好\\n'\n"]],
                ["type": "step_finish", "part": ["reason": "stop"]],
            ]
        case .os: return
        }
        let data = try jsonLines(events)
        // Real pipes may split any UTF-8 scalar and any JSON delimiter.
        for byte in data { try decoder.receive(Data([byte])) }
        try decoder.finish()
        #expect(decoder.text == script)
    }

    @Test("Grok also accepts unwrapped Messages-format events")
    func unwrappedMessages() throws {
        var decoder = ScriptGenerationOutput(provider: .grok)
        try decoder.receive(
            jsonLines([
                ["type": "message_start"],
                ["type": "content_block_delta", "delta": ["type": "text_delta", "text": script]],
            ]))
        #expect(decoder.text == script)
    }

    @Test("Semantic failures invalidate partial code even if the process exits successfully")
    func semanticFailures() throws {
        let failures: [(ScriptGenerationProvider, [String: Any])] = [
            (.codex, ["type": "turn.failed", "error": ["message": "authentication required"]]),
            (.claude, ["type": "result", "is_error": true, "errors": ["quota"]]),
            (.gemini, ["type": "result", "status": "error", "error": ["message": "quota"]]),
            (.copilot, ["type": "session.error", "data": ["message": "quota"]]),
            (.grok, ["type": "message_delta", "delta": ["stop_reason": "max_tokens"]]),
            (.opencode, ["type": "error", "error": ["data": ["message": "quota"]]]),
        ]
        for (provider, event) in failures {
            var decoder = ScriptGenerationOutput(provider: provider)
            let data = try jsonLines([event])
            #expect(throws: ScriptGenerationError.self) { try decoder.receive(data) }
        }
    }

    @Test("Incomplete JSON and terminal output cannot become source")
    func invalidTransport() throws {
        var decoder = ScriptGenerationOutput(provider: .codex)
        try decoder.receive(Data("{\"type\":".utf8))
        #expect(throws: ScriptGenerationError.self) { try decoder.finish() }
        var other = ScriptGenerationOutput(provider: .claude)
        #expect(throws: ScriptGenerationError.self) { try other.receive(Data("Please log in\n".utf8)) }
    }

    @Test("Code fences are removed without trimming source indentation or here-documents")
    func codeValidation() throws {
        let code = "#!/bin/sh\ncat <<'EOF'\n  keep spacing\nEOF\n"
        #expect(
            try ScriptGenerationOutput.validatedScript("```sh\n" + code + "```", preservingShebang: "#!/bin/sh") == code
        )
        #expect(try ScriptGenerationOutput.validatedScript(code, preservingShebang: "#!/bin/sh") == code)
        for invalid in ["", "Here is the script:\n" + code, "#!/bin/zsh\necho changed", "--- old\n+++ new"] {
            #expect(throws: ScriptGenerationError.self) {
                try ScriptGenerationOutput.validatedScript(invalid, preservingShebang: "#!/bin/sh")
            }
        }
    }

    @Test("Generating without an original shebang still requires a runnable result")
    func newScriptValidation() throws {
        #expect(try ScriptGenerationOutput.validatedScript(script, preservingShebang: nil) == script)
        for invalid in [
            "", "echo missing", "#!sh\necho malformed", "#!/nonexistent/taptick-interpreter\necho unavailable",
            "\n" + script, " " + script, "\u{FEFF}" + script, "--- old\n+++ new",
        ] {
            #expect(throws: ScriptGenerationError.self) {
                try ScriptGenerationOutput.validatedScript(invalid, preservingShebang: nil)
            }
        }
    }

    @Test("Placeholder expansion is literal and non-recursive")
    func promptExpansion() {
        let source = "#!/bin/sh\necho '{{script}}'\necho '$HOME `whoami` $(whoami)'"
        let request = ScriptGenerationRequest(source: source, prompt: "Edit:\n{{script}}")
        #expect(request.expandedPrompt == "Edit:\n" + source)
        #expect(
            ScriptGenerationRequest(source: source, prompt: "Create a new script").expandedPrompt
                == "Create a new script")
    }

    private func jsonLines(_ events: [[String: Any]]) throws -> Data {
        try events.reduce(into: Data()) { result, event in
            result.append(try JSONSerialization.data(withJSONObject: event, options: [.withoutEscapingSlashes]))
            result.append(10)
        }
    }
}

@Suite("Generation process and request lifecycle")
@MainActor
struct GenerationProcessTests {
    @Test("Process preserves argument boundaries and separates stderr")
    func channelsAndArguments() async throws {
        var stdout = Data()
        let argument = "hello '你好' $HOME `whoami` $(whoami)\nlast line"
        let result = try await GenerationProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s' \"$1\"; printf 'diagnostic' >&2; exit 7", "fixture", argument],
            environment: ScriptExecutionEnvironment.environment, directory: FileManager.default.temporaryDirectory
        ) { stdout.append($0) }
        #expect(String(decoding: stdout, as: UTF8.self) == argument)
        #expect(result.diagnostic == "diagnostic")
        #expect(result.exitCode == 7)
    }

    @Test("Cancellation terminates a child retaining the output pipe")
    func cancelsProcessGroup() async throws {
        var output = Data()
        let process = GenerationProcess()
        let task = Task {
            try await process.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 30 & printf '%s\\n' $!; wait"],
                environment: ScriptExecutionEnvironment.environment, directory: FileManager.default.temporaryDirectory,
                timeout: .seconds(5)
            ) { output.append($0) }
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now + .seconds(3)
        while output.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let pid = try #require(
            Int32(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // The shell or launchd may need a brief interval to reap the terminated child.
        let reapDeadline = ContinuousClock.now + .seconds(2)
        while kill(pid, 0) == 0, ContinuousClock.now < reapDeadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(kill(pid, 0) == -1)
    }

    @Test("Timeout and output limits stop a running command")
    func resourceLimits() async throws {
        await #expect(throws: ScriptGenerationError.self) {
            try await GenerationProcess().run(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 30"],
                environment: ScriptExecutionEnvironment.environment, directory: FileManager.default.temporaryDirectory,
                timeout: .milliseconds(50)
            ) { _ in }
        }
        await #expect(throws: ScriptGenerationError.self) {
            try await GenerationProcess().run(
                executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [],
                environment: ScriptExecutionEnvironment.environment, directory: FileManager.default.temporaryDirectory,
                outputLimit: 64
            ) { _ in }
        }
    }

    @Test("A cancelled request cannot publish completion into a replacement request")
    func staleRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try """
        #!/bin/sh
        sleep 0.2
        printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"#!/bin/sh\\necho done\\n"}}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let service = ScriptGenerationService(availability: [.codex: .init(executable: executable)])
        var oldCompleted = false
        var replacement: String?
        let request = ScriptGenerationRequest(source: "#!/bin/sh\necho old\n", prompt: "{{script}}")
        service.generate(provider: .codex, request: request) { _ in oldCompleted = true }
        service.cancel()
        service.generate(provider: .codex, request: request) { replacement = $0 }
        let deadline = ContinuousClock.now + .seconds(4)
        while service.isGenerating, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!oldCompleted)
        #expect(replacement == "#!/bin/sh\necho done\n")
        #expect(service.error == nil)
    }

    @Test(
        "Generation accepts empty scripts and repairs missing, malformed, or unavailable shebangs",
        arguments: ["", "echo old\n", "#!sh\necho old\n", "#!/nonexistent/taptick-interpreter\necho old\n"]
    )
    func repairsShebang(_ source: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try """
        #!/bin/sh
        printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"#!/bin/sh\\necho done\\n"}}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let service = ScriptGenerationService(availability: [.codex: .init(executable: executable)])
        defer { service.cancel() }
        var replacement: String?
        service.generate(provider: .codex, request: ScriptGenerationRequest(source: source, prompt: "Fix {{script}}")) {
            replacement = $0
        }
        let deadline = ContinuousClock.now + .seconds(4)
        while service.isGenerating, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!service.isGenerating)
        #expect(service.error == nil)
        #expect(replacement == "#!/bin/sh\necho done\n")
    }

    @Test("Executable discovery ignores relative paths and directories")
    func executableDiscovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidate = directory.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        #expect(ScriptGenerationService.resolveExecutable(named: "fixture", path: directory.path) == nil)
        try FileManager.default.removeItem(at: candidate)
        try "#!/bin/sh\n".write(to: candidate, atomically: true, encoding: .utf8)
        #expect(ScriptGenerationService.resolveExecutable(named: "fixture", path: directory.path) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: candidate.path)
        #expect(ScriptGenerationService.resolveExecutable(named: "fixture", path: ".:" + directory.path) == candidate)
    }

    @Test("CLI capability detection accepts help on stderr")
    func helpOnStderr() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("opencode")
        try "#!/bin/sh\nprintf '%s\\n' '--format --agent --pure' >&2\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = await ScriptGenerationService.inspect(.opencode, environment: ["PATH": directory.path])
        #expect(result.isAvailable)
        #expect(result.executable == executable)
    }
}
