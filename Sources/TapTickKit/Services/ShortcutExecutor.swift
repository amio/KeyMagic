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
        case .runScript(let script, let shell):
            runInlineScript(script: script, shell: shell, shortcutID: shortcutID)
        case .runScriptFile(let path, let shell):
            runScriptFile(path: path, shell: shell, shortcutID: shortcutID)
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

    private func runInlineScript(
        script: String,
        shell: ShortcutAction.ShellType,
        shortcutID: UUID?
    ) {
        let callback = onScriptCompleted
        Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = ["-c", script]
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

                if let shortcutID, let callback {
                    let log = ScriptExecutionLog(
                        shortcutID: shortcutID,
                        output: output,
                        exitCode: exitCode,
                        timestamp: Date()
                    )
                    await callback(log)
                }
            } catch {
                print("TapTick: Failed to run script: \(error)")
                if let shortcutID, let callback {
                    let log = ScriptExecutionLog(
                        shortcutID: shortcutID,
                        output: "Error: \(error.localizedDescription)",
                        exitCode: -1,
                        timestamp: Date()
                    )
                    await callback(log)
                }
            }
        }
    }

    private func runScriptFile(
        path: String,
        shell: ShortcutAction.ShellType,
        shortcutID: UUID?
    ) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            print("TapTick: Script file not found: \(expandedPath)")
            if let shortcutID, let callback = onScriptCompleted {
                let log = ScriptExecutionLog(
                    shortcutID: shortcutID,
                    output: "Script file not found: \(expandedPath)",
                    exitCode: -1,
                    timestamp: Date()
                )
                callback(log)
            }
            return
        }

        let callback = onScriptCompleted
        Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = [expandedPath]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus

                if exitCode != 0 {
                    print("TapTick: Script file exited with code \(exitCode)")
                }

                if let shortcutID, let callback {
                    let log = ScriptExecutionLog(
                        shortcutID: shortcutID,
                        output: output,
                        exitCode: exitCode,
                        timestamp: Date()
                    )
                    await callback(log)
                }
            } catch {
                print("TapTick: Failed to run script file: \(error)")
                if let shortcutID, let callback {
                    let log = ScriptExecutionLog(
                        shortcutID: shortcutID,
                        output: "Error: \(error.localizedDescription)",
                        exitCode: -1,
                        timestamp: Date()
                    )
                    await callback(log)
                }
            }
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