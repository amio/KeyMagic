import Foundation

/** A shell command accepted by the low-level script process boundary. */
enum ScriptCommand: Equatable, Hashable, Sendable {
    case inline(script: String, shell: ShortcutAction.ShellType)
    case file(path: String, shell: ShortcutAction.ShellType)
}

extension ShortcutAction {
    var scriptCommand: ScriptCommand? {
        switch self {
        case .runScript(let script, let shell):
            .inline(script: script, shell: shell)
        case .runScriptFile(let path, let shell):
            .file(path: path, shell: shell)
        case .launchApp:
            nil
        }
    }
}

/** How a script invocation reached its terminal state. */
enum ScriptTermination: Equatable, Sendable {
    case exited(Int32)
    case failed(String)

    var exitCode: Int32 {
        switch self {
        case .exited(let exitCode):
            exitCode
        case .failed:
            -1
        }
    }
}

/** Canonical facts produced by one script process invocation. */
struct ScriptExecutionResult: Sendable {
    let output: String
    let termination: ScriptTermination
    let startedAt: Date
    let duration: TimeInterval

    init(
        output: String,
        termination: ScriptTermination,
        startedAt: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.output = output
        self.termination = termination
        self.startedAt = startedAt
        self.duration = duration
    }

    init(
        output: String,
        exitCode: Int32,
        startedAt: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.init(
            output: output,
            termination: exitCode == -1 ? .failed(output) : .exited(exitCode),
            startedAt: startedAt,
            duration: duration
        )
    }

    var exitCode: Int32 { termination.exitCode }
    var succeeded: Bool { termination == .exited(0) }

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

/** Stateless, injectable owner of shell process setup, output capture, and termination. */
struct ScriptRunner: Sendable {
    private let operation: @Sendable (ScriptCommand) async -> ScriptExecutionResult

    init(operation: @escaping @Sendable (ScriptCommand) async -> ScriptExecutionResult) {
        self.operation = operation
    }

    func run(_ command: ScriptCommand) async -> ScriptExecutionResult {
        await operation(command)
    }

    static let live = ScriptRunner { command in
        await runProcess(command)
    }

    private static func runProcess(_ command: ScriptCommand) async -> ScriptExecutionResult {
        let startedAt = Date()
        let startedUptime = DispatchTime.now().uptimeNanoseconds
        let elapsed: () -> TimeInterval = {
            TimeInterval(DispatchTime.now().uptimeNanoseconds - startedUptime) / 1_000_000_000
        }
        let process = Process()
        let pipe = Pipe()

        switch command {
        case .inline(let script, let shell):
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = ["-c", script]
        case .file(let path, let shell):
            let expandedPath = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                let message = "Script file not found: \(expandedPath)"
                return ScriptExecutionResult(
                    output: message,
                    termination: .failed(message),
                    startedAt: startedAt,
                    duration: elapsed()
                )
            }

            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = [expandedPath]
        }

        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let outputHandle = pipe.fileHandleForReading
            let outputTask = Task.detached(priority: .userInitiated) {
                try outputHandle.readToEnd() ?? Data()
            }

            process.waitUntilExit()
            let data = try await outputTask.value
            let output = String(decoding: data, as: UTF8.self)
            let exitCode = process.terminationStatus

            if exitCode != 0 {
                print("TapTick: Script exited with code \(exitCode)")
            }

            return ScriptExecutionResult(
                output: output,
                termination: .exited(exitCode),
                startedAt: startedAt,
                duration: elapsed()
            )
        } catch {
            let message = "Error: \(error.localizedDescription)"
            print("TapTick: Failed to run script: \(error)")
            return ScriptExecutionResult(
                output: message,
                termination: .failed(message),
                startedAt: startedAt,
                duration: elapsed()
            )
        }
    }
}
