import Foundation
import FoundationModels
import Observation

/// Owns provider discovery and one generation request. Only the current request may publish;
/// the native editor owns preview/commit, and ShortcutStore remains the only persistence boundary.
@MainActor
@Observable
final class ScriptGenerationService {
    private(set) var availability: [ScriptGenerationProvider: ScriptGenerationAvailability] = [:]
    private(set) var isDiscovering = false
    private(set) var isGenerating = false
    private(set) var preview: String?
    var error: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var environment = ScriptExecutionEnvironment.environment

    init(availability: [ScriptGenerationProvider: ScriptGenerationAvailability] = [:]) {
        self.availability = availability
    }

    func status(for provider: ScriptGenerationProvider) -> ScriptGenerationAvailability {
        if provider == .os { return .system }
        return availability[provider] ?? ScriptGenerationAvailability(issue: "Checking installation…")
    }

    func refresh() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        environment = await Self.cliEnvironment()
        let environment = environment
        let probes = ScriptGenerationProvider.allCases.filter { $0 != .os }.map { provider in
            (provider, Task { await Self.inspect(provider, environment: environment) })
        }
        for (provider, probe) in probes {
            availability[provider] = await probe.value
        }
    }

    func generate(
        provider: ScriptGenerationProvider,
        request: ScriptGenerationRequest,
        onCompletion: @escaping @MainActor (String?) -> Void
    ) {
        guard !isGenerating else { return }
        let status = status(for: provider)
        guard status.isAvailable else {
            error = status.issue
            onCompletion(nil)
            return
        }
        let id = UUID()
        requestID = id
        isGenerating = true
        preview = nil
        error = nil
        let environment = environment
        task = Task {
            do {
                let response: String
                if provider == .os {
                    let session = LanguageModelSession(instructions: request.instructions)
                    var latest = ""
                    var lastPublication = ContinuousClock.now
                    for try await snapshot in session.streamResponse(to: request.expandedPrompt) {
                        try Task.checkCancellation()
                        latest = snapshot.content
                        if ContinuousClock.now - lastPublication >= .milliseconds(60) {
                            publish(latest, for: id)
                            lastPublication = .now
                        }
                    }
                    response = latest
                } else {
                    guard let executable = status.executable else {
                        throw ScriptGenerationError(message: "The selected AI tool is not installed.")
                    }
                    response = try await generateWithCLI(
                        provider: provider, executable: executable, request: request,
                        environment: environment, id: id
                    )
                }
                try Task.checkCancellation()
                let script = try ScriptGenerationOutput.validatedScript(
                    response, preservingShebang: request.preservedShebang)
                guard requestID == id else { return }
                finish()
                onCompletion(script)
            } catch {
                guard requestID == id else { return }
                let wasCancelled = Task.isCancelled
                finish()
                if !wasCancelled { self.error = "\(provider.title): \(error.localizedDescription)" }
                onCompletion(nil)
            }
        }
    }

    func cancel() {
        task?.cancel()
        finish()
    }

    private func finish() {
        task = nil
        requestID = nil
        isGenerating = false
        preview = nil
    }

    private func publish(_ text: String, for id: UUID) {
        guard requestID == id, !text.isEmpty else { return }
        preview = text
    }

    private func generateWithCLI(
        provider: ScriptGenerationProvider, executable: URL, request: ScriptGenerationRequest,
        environment: [String: String], id: UUID
    ) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TapTick-Generate-\(id)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let invocation = try ScriptGenerationInvocation.prepare(
            provider: provider, request: request, directory: directory, environment: environment
        )
        var decoder = ScriptGenerationOutput(provider: provider)
        var lastPublication = ContinuousClock.now
        let result = try await GenerationProcess().run(
            executable: executable, arguments: invocation.arguments,
            environment: invocation.environment, directory: directory, input: invocation.input
        ) { data in
            try decoder.receive(data)
            if ContinuousClock.now - lastPublication >= .milliseconds(60) {
                self.publish(decoder.text, for: id)
                lastPublication = .now
            }
        }
        try decoder.finish()
        guard result.exitCode == 0 else {
            let detail =
                result.diagnostic.isEmpty
                ? "Check the tool's login and model configuration."
                : String(result.diagnostic.suffix(2000))
            throw ScriptGenerationError(message: "Exited with code \(result.exitCode). \(detail)")
        }
        return decoder.text
    }

    static func resolveExecutable(named name: String, path: String) -> URL? {
        path.components(separatedBy: ":").filter { $0.hasPrefix("/") }.lazy
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name) }
            .first {
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: $0.path)
            }
    }

    static func inspect(
        _ provider: ScriptGenerationProvider, environment: [String: String]
    ) async -> ScriptGenerationAvailability {
        guard let executable = resolveExecutable(named: provider.rawValue, path: environment["PATH"] ?? "") else {
            return ScriptGenerationAvailability(issue: "Not installed")
        }
        let arguments: [String]
        switch provider {
        case .codex: arguments = ["exec", "--help"]
        case .opencode: arguments = ["run", "--help"]
        case .grok: arguments = ["--no-auto-update", "--help"]
        case .copilot: arguments = ["--no-auto-update", "--help"]
        default: arguments = ["--help"]
        }
        do {
            var output = Data()
            let result = try await GenerationProcess().run(
                executable: executable, arguments: arguments, environment: environment,
                directory: FileManager.default.temporaryDirectory,
                timeout: .seconds(8), outputLimit: 128 * 1024
            ) { output.append($0) }
            // Some CLIs, including OpenCode, intentionally print help to stderr.
            let help = String(decoding: output, as: UTF8.self) + "\n" + result.diagnostic
            guard result.exitCode == 0 else {
                return ScriptGenerationAvailability(issue: "Cannot start — check the CLI installation")
            }
            guard provider.requiredFlags.allSatisfy({ help.contains($0) }) else {
                return ScriptGenerationAvailability(issue: "CLI version is not supported — update it")
            }
            return ScriptGenerationAvailability(executable: executable)
        } catch {
            return ScriptGenerationAvailability(issue: "Cannot start — \(error.localizedDescription)")
        }
    }

    private static func cliEnvironment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = (environment["PATH"] ?? "").components(separatedBy: ":")
        // GUI apps do not inherit the terminal's PATH. Delimit the one requested value so
        // shell startup banners cannot become executable search paths.
        let shell = environment["SHELL"] ?? "/bin/zsh"
        if shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) {
            var output = Data()
            _ = try? await GenerationProcess().run(
                executable: URL(fileURLWithPath: shell),
                arguments: ["-ilc", "printf '\\0%s\\0' \"$PATH\""], environment: environment,
                directory: FileManager.default.temporaryDirectory,
                timeout: .seconds(3), outputLimit: 64 * 1024
            ) { output.append($0) }
            let fields = output.split(separator: 0, omittingEmptySubsequences: false)
            if fields.count >= 3 { paths += String(decoding: fields[1], as: UTF8.self).components(separatedBy: ":") }
        }
        paths += ScriptExecutionEnvironment.pathEntries + ["\(home)/.grok/bin", "\(home)/.opencode/bin"]
        var seen = Set<String>()
        environment["PATH"] = paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }
}
