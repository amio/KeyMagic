import Cocoa
import Foundation
import Observation

/**
 Owns user-initiated shortcut execution for the process lifetime.

 Hotkeys, menu items, and Editor Run all enter here. Background menu-bar refreshes intentionally
 bypass this policy owner and reuse only `ScriptRunner` so they cannot affect explicit logs or HUDs.
 */
@MainActor
@Observable
public final class ShortcutExecutor {
    @ObservationIgnored private let store: ShortcutStore
    @ObservationIgnored private let scriptRunner: ScriptRunner
    @ObservationIgnored private let logStore: ScriptLogStore
    @ObservationIgnored private let presentOutput: @MainActor @Sendable (ScriptExecutionLog) -> Void
    private let applicationLauncher: ApplicationLauncher

    public private(set) var activeRunIDs: Set<UUID> = []

    public convenience init(
        store: ShortcutStore,
        logStore: ScriptLogStore,
        outputPresenter: ScriptOutputPresenter
    ) {
        self.init(
            store: store,
            scriptRunner: .live,
            logStore: logStore,
            presentOutput: { log in outputPresenter.show(log: log) },
            applicationLauncher: .live
        )
    }

    init(
        store: ShortcutStore,
        scriptRunner: ScriptRunner,
        logStore: ScriptLogStore,
        presentOutput: @escaping @MainActor @Sendable (ScriptExecutionLog) -> Void,
        applicationLauncher: ApplicationLauncher = .live
    ) {
        self.store = store
        self.scriptRunner = scriptRunner
        self.logStore = logStore
        self.presentOutput = presentOutput
        self.applicationLauncher = applicationLauncher
    }

    /** Executes the latest stored action and returns an ID for an asynchronous script run. */
    @discardableResult
    public func execute(shortcutID: UUID) -> UUID? {
        guard let shortcut = store.shortcuts.first(where: { $0.id == shortcutID }) else {
            return nil
        }

        store.markTriggered(id: shortcutID)
        switch shortcut.action {
        case .launchApp(let bundleIdentifier, _):
            toggleOrLaunchApp(bundleIdentifier: bundleIdentifier)
            return nil
        case .runScript, .runScriptFile:
            guard let command = store.scriptCommand(for: shortcutID) else { return nil }
            return runScript(command: command, shortcutID: shortcutID)
        }
    }

    public func isRunning(runID: UUID) -> Bool {
        activeRunIDs.contains(runID)
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

    private func runScript(command: ScriptCommand, shortcutID: UUID) -> UUID {
        let runID = UUID()
        activeRunIDs.insert(runID)
        let scriptRunner = scriptRunner

        Task { [weak self, scriptRunner] in
            let result = await scriptRunner.run(command)
            guard let self else { return }

            activeRunIDs.remove(runID)
            let log = ScriptExecutionLog(shortcutID: shortcutID, result: result)
            logStore.record(log)
            presentOutput(log)
        }
        return runID
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
