import Cocoa
import Foundation

/// Executes shortcut actions (toggle app visibility/focus, run scripts).
@MainActor
final class ShortcutExecutor {
    private let applicationLauncher: ApplicationLauncher

    /// Called on the main actor after a script finishes with its captured output.
    var onScriptCompleted: (@MainActor @Sendable (ScriptExecutionLog) -> Void)?

    init(applicationLauncher: ApplicationLauncher = .live) {
        self.applicationLauncher = applicationLauncher
    }

    /// Execute the given action, optionally associating it with a shortcut for logging.
    func execute(action: ShortcutAction, shortcutID: UUID? = nil) {
        switch action {
        case .launchApp(let bundleIdentifier, _):
            toggleOrLaunchApp(bundleIdentifier: bundleIdentifier)
        case .runScript, .runScriptFile:
            runScript(action: action, shortcutID: shortcutID)
        }
    }

    // MARK: - Toggle App Visibility / Focus

    private func toggleOrLaunchApp(bundleIdentifier: String) {
        let runningApps = applicationLauncher.runningApplications(bundleIdentifier)

        if let app = activeRunningApplication(in: runningApps) {
            let didHide = app.hide()
            if didHide {
                return
            }

            print("TapTick: Failed to hide active app: \(bundleIdentifier)")
            return
        }

        if let app = preferredRunningApplication(in: runningApps) {
            app.unhide()

            let didActivate = app.activate([.activateAllWindows])
            if didActivate {
                return
            }

            print("TapTick: Failed to activate running app: \(bundleIdentifier)")
        }

        launchApp(bundleIdentifier: bundleIdentifier)
    }

    private func activeRunningApplication(
        in runningApps: [RunningApplicationHandle]
    ) -> RunningApplicationHandle? {
        runningApps.first {
            $0.isActive && ($0.activationPolicy == .regular || $0.activationPolicy == .accessory)
        }
    }

    private func preferredRunningApplication(
        in runningApps: [RunningApplicationHandle]
    ) -> RunningApplicationHandle? {
        // Bundle IDs can own background helpers as well as the user-facing app process.
        // Prefer a window-capable instance and let Launch Services recover otherwise.
        return runningApps.first { $0.activationPolicy == .regular }
            ?? runningApps.first { $0.activationPolicy == .accessory }
    }

    private func launchApp(bundleIdentifier: String) {
        guard let url = applicationLauncher.applicationURL(bundleIdentifier) else {
            print("TapTick: App not found: \(bundleIdentifier)")
            return
        }

        applicationLauncher.openApplication(url) { error in
            if let error {
                print("TapTick: Failed to launch app: \(error)")
            }
        }
    }

    // MARK: - Run Script

    private func runScript(action: ShortcutAction, shortcutID: UUID?) {
        let callback = onScriptCompleted
        Task.detached(priority: .userInitiated) {
            let result = await Self.executeScript(action: action)
            if let shortcutID, let callback {
                let log = ScriptExecutionLog(
                    shortcutID: shortcutID,
                    output: result.output,
                    exitCode: result.exitCode,
                    timestamp: Date(),
                    duration: result.duration
                )
                await callback(log)
            }
        }
    }

    nonisolated static func executeScript(action: ShortcutAction) async -> ScriptExecutionResult {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let elapsed: () -> TimeInterval = {
            TimeInterval(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        }
        let process = Process()
        let pipe = Pipe()

        switch action {
        case .runScript(let script, let shell):
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = ["-c", script]
        case .runScriptFile(let path, let shell):
            let expandedPath = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                print("TapTick: Script file not found: \(expandedPath)")
                return ScriptExecutionResult(
                    output: "Script file not found: \(expandedPath)",
                    exitCode: -1,
                    duration: elapsed()
                )
            }

            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = [expandedPath]
        case .launchApp:
            return ScriptExecutionResult(
                output: "Error: Not a script action.",
                exitCode: -1,
                duration: elapsed()
            )
        }

        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus

            if exitCode != 0 {
                print("TapTick: Script exited with code \(exitCode)")
            }

            return ScriptExecutionResult(
                output: output,
                exitCode: exitCode,
                duration: elapsed()
            )
        } catch {
            print("TapTick: Failed to run script: \(error)")
            return ScriptExecutionResult(
                output: "Error: \(error.localizedDescription)",
                exitCode: -1,
                duration: elapsed()
            )
        }
    }
}

/** Lightweight handle for a running app process so launch/focus behavior is testable. */
struct RunningApplicationHandle {
    let activationPolicy: NSApplication.ActivationPolicy
    let isActive: Bool
    let hide: () -> Bool
    let unhide: () -> Void
    let activate: (NSApplication.ActivationOptions) -> Bool
}

/** Owns the Launch Services boundary used for application shortcuts. */
struct ApplicationLauncher {
    let runningApplications: (String) -> [RunningApplicationHandle]
    let applicationURL: (String) -> URL?
    let openApplication: (URL, @escaping @Sendable (Error?) -> Void) -> Void

    @MainActor
    static let live = ApplicationLauncher(
        runningApplications: { bundleIdentifier in
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == bundleIdentifier }
                .map { RunningApplicationHandle($0) }
        },
        applicationURL: { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        openApplication: { url, completion in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                completion(error)
            }
        }
    )
}

private extension RunningApplicationHandle {
    init(_ application: NSRunningApplication) {
        self.init(
            activationPolicy: application.activationPolicy,
            isActive: application.isActive,
            hide: {
                application.hide()
            },
            unhide: {
                application.unhide()
            },
            activate: { options in
                application.activate(options: options)
            }
        )
    }
}
