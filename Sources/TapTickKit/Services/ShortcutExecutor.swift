import Cocoa
import Foundation

/// Executes shortcut actions (toggle app visibility/focus, run scripts).
@MainActor
final class ShortcutExecutor {
    private let applicationLauncher: ApplicationLauncher

    init(applicationLauncher: ApplicationLauncher = .live) {
        self.applicationLauncher = applicationLauncher
    }

    /// Execute the given action.
    func execute(action: ShortcutAction) {
        switch action {
        case .launchApp(let bundleIdentifier, _):
            toggleOrLaunchApp(bundleIdentifier: bundleIdentifier)
        case .runScript(let script, let shell):
            runInlineScript(script: script, shell: shell)
        case .runScriptFile(let path, let shell):
            runScriptFile(path: path, shell: shell)
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

    private func runInlineScript(script: String, shell: ShortcutAction.ShellType) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = ["-c", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    print("TapTick: Script exited with code \(process.terminationStatus)")
                }
            } catch {
                print("TapTick: Failed to run script: \(error)")
            }
        }
    }

    private func runScriptFile(path: String, shell: ShortcutAction.ShellType) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            print("TapTick: Script file not found: \(expandedPath)")
            return
        }

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell.rawValue)
            process.arguments = [expandedPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    print("TapTick: Script exited with code \(process.terminationStatus)")
                }
            } catch {
                print("TapTick: Failed to run script file: \(error)")
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
