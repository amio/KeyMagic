import Darwin
import Foundation

struct ScriptGenerationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Owns one CLI process group. Output channels stay separate; cancellation also stops children
/// holding the pipes open. This boundary is independent of non-cancellable user script runs.
@MainActor
final class GenerationProcess {
    struct Result: Sendable {
        let exitCode: Int32
        let diagnostic: String
    }

    private var processID: pid_t?
    private var terminationTask: Task<Void, Never>?
    private var didCancel = false
    private var didTimeOut = false

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL,
        input: URL? = nil,
        timeout: Duration = .seconds(300),
        outputLimit: Int = 4 * 1024 * 1024,
        onOutput: @escaping @MainActor @Sendable (Data) throws -> Void
    ) async throws -> Result {
        try Task.checkCancellation()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = try FileHandle(forReadingFrom: input ?? URL(fileURLWithPath: "/dev/null"))
        defer { try? stdin.close() }

        processID = try spawn(
            executable: executable, arguments: arguments, environment: environment,
            directory: directory, stdin: stdin, stdout: stdout, stderr: stderr
        )
        try stdout.fileHandleForWriting.close()
        try stderr.fileHandleForWriting.close()
        guard let pid = processID else { throw ScriptGenerationError(message: "Could not start the AI tool.") }

        let deadline = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                guard let self else { return }
                didTimeOut = true
                terminate()
            } catch {}
        }
        defer {
            deadline.cancel()
            terminationTask?.cancel()
            terminationTask = nil
            // A CLI may exit before a helper that inherited its pipes or process group.
            kill(-pid, SIGKILL)
            processID = nil
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
        }

        return try await withTaskCancellationHandler {
            let output = Task.detached {
                do {
                    var byteCount = 0
                    while let data = try await Self.blocking({ try Self.readChunk(stdout.fileHandleForReading) }) {
                        byteCount += data.count
                        guard byteCount <= outputLimit else {
                            throw ScriptGenerationError(message: "The AI tool returned too much output.")
                        }
                        try await onOutput(data)
                    }
                } catch {
                    await self.terminate()
                    throw error
                }
            }
            let diagnostic = Task.detached {
                try await Self.blocking {
                    var tail = Data()
                    while let data = try Self.readChunk(stderr.fileHandleForReading) {
                        tail.append(data)
                        if tail.count > 16_384 { tail = Data(tail.suffix(16_384)) }
                    }
                    return String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let status = try await Self.blocking {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 {
                    if errno != EINTR { return Int32(-1) }
                }
                return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            }
            let outputResult = await output.result
            let diagnosticResult = await diagnostic.result
            if didCancel || Task.isCancelled { throw CancellationError() }
            if didTimeOut { throw ScriptGenerationError(message: "The AI tool timed out. Try again.") }
            try outputResult.get()
            return Result(exitCode: status, diagnostic: try diagnosticResult.get())
        } onCancel: {
            Task { @MainActor in
                self.didCancel = true
                self.terminate()
            }
        }
    }

    private func terminate() {
        guard let processID, terminationTask == nil else { return }
        kill(-processID, SIGTERM)
        terminationTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                kill(-processID, SIGKILL)
            } catch {}
        }
    }

    // Concurrent discovery can have several pipes open. Blocking IO must not occupy the
    // cooperative Swift executor needed to deliver their data, cancellation, and deadlines.
    nonisolated private static func blocking<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Swift.Result(catching: operation))
            }
        }
    }

    // FileHandle.read(upToCount:) can wait to fill the requested buffer on macOS. A single
    // read(2) returns the currently available pipe bytes, which is essential for live output.
    nonisolated private static func readChunk(_ handle: FileHandle) throws -> Data? {
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            }
            if count == 0 { return nil }
            if count > 0 { return Data(bytes.prefix(count)) }
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }

    private func spawn(
        executable: URL, arguments: [String], environment: [String: String], directory: URL,
        stdin: FileHandle, stdout: Pipe, stderr: Pipe
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_adddup2(&actions, stdin.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        let directoryError = posix_spawn_file_actions_addchdir(&actions, directory.path)
        guard directoryError == 0 else { throw POSIXError(POSIXErrorCode(rawValue: directoryError) ?? .EIO) }

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let error = argv.withUnsafeBufferPointer { argv in
            envp.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, executable.path, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
        return pid
    }
}
