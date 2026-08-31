import AppKit
import Testing
@testable import TapTickKit

@MainActor
@Suite("ShortcutExecutor")
struct ShortcutExecutorTests {
    @Test("Launch app hides the active running instance")
    func hidesActiveRunningApplication() {
        let app = TestRunningApplication(activationPolicy: .regular, isActive: true)
        var openedURL: URL?

        let context = makeContext(
            action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"),
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [app.handle] },
                applicationURL: { _ in URL(fileURLWithPath: "/Applications/Test.app") },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )
        defer { context.removeDirectory() }

        context.executor.execute(shortcutID: context.shortcut.id)

        #expect(app.didHide)
        #expect(app.didUnhide == false)
        #expect(app.activationOptions == nil)
        #expect(openedURL == nil)
    }

    @Test("Launch app focuses an activatable running instance")
    func focusesRunningApplication() {
        let app = TestRunningApplication(activationPolicy: .regular)
        var openedURL: URL?

        let context = makeContext(
            action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"),
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [app.handle] },
                applicationURL: { _ in URL(fileURLWithPath: "/Applications/Test.app") },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )
        defer { context.removeDirectory() }

        context.executor.execute(shortcutID: context.shortcut.id)

        #expect(app.didUnhide)
        #expect(app.activationOptions == [.activateAllWindows])
        #expect(openedURL == nil)
    }

    @Test("Launch app falls back to Launch Services when only helpers are running")
    func launchesWhenOnlyHelpersExist() {
        let helper = TestRunningApplication(activationPolicy: .prohibited)
        let expectedURL = URL(fileURLWithPath: "/Applications/Test.app")
        var openedURL: URL?

        let context = makeContext(
            action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"),
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [helper.handle] },
                applicationURL: { _ in expectedURL },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )
        defer { context.removeDirectory() }

        context.executor.execute(shortcutID: context.shortcut.id)

        #expect(helper.didUnhide == false)
        #expect(helper.activationOptions == nil)
        #expect(openedURL == expectedURL)
    }

    @Test("Launch app falls back to Launch Services when activation fails")
    func relaunchesWhenActivationFails() {
        let app = TestRunningApplication(activationPolicy: .regular, activationResult: false)
        let expectedURL = URL(fileURLWithPath: "/Applications/Test.app")
        var openedURL: URL?

        let context = makeContext(
            action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"),
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [app.handle] },
                applicationURL: { _ in expectedURL },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )
        defer { context.removeDirectory() }

        context.executor.execute(shortcutID: context.shortcut.id)

        #expect(app.didUnhide)
        #expect(app.activationOptions == [.activateAllWindows])
        #expect(openedURL == expectedURL)
    }

    @Test("Explicit script execution owns progress, logging, trigger metadata, and presentation")
    func explicitScriptExecutionPipeline() async throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        let result = ScriptExecutionResult(
            output: "trigger",
            exitCode: 0,
            startedAt: startedAt,
            duration: 0.25
        )
        let presenter = TestScriptPresentationRecorder()
        let context = makeContext(
            action: .runScript(script: "#!/bin/sh\nprintf trigger"),
            scriptRunner: ScriptRunner { _ in result },
            presentOutput: { log in presenter.logs.append(log) }
        )
        defer { context.removeDirectory() }

        let runID = try #require(context.executor.execute(shortcutID: context.shortcut.id))
        #expect(context.executor.isRunning(runID: runID))

        for _ in 0..<100 where context.executor.isRunning(runID: runID) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let log = try #require(context.logStore.recentLogs(for: context.shortcut.id).first)
        #expect(!context.executor.isRunning(runID: runID))
        #expect(context.store.shortcuts.first?.lastTriggeredAt != nil)
        #expect(log.output == "trigger")
        #expect(log.timestamp == startedAt)
        #expect(log.duration == 0.25)
        #expect(presenter.logs.map(\.id) == [log.id])
    }

    private func makeContext(
        action: ShortcutAction,
        scriptRunner: ScriptRunner = ScriptRunner { _ in
            ScriptExecutionResult(output: "", exitCode: 0)
        },
        presentOutput: @escaping @MainActor @Sendable (ScriptExecutionLog) -> Void = { _ in },
        applicationLauncher: ApplicationLauncher = .live
    ) -> ExecutionTestContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickShortcutExecutor-\(UUID().uuidString)")
        let store = ShortcutStore(directory: directory)
        let logStore = ScriptLogStore(directory: directory)
        let shortcut = Shortcut(name: "Test", action: action)
        store.add(shortcut)
        let executor = ShortcutExecutor(
            store: store,
            scriptRunner: scriptRunner,
            logStore: logStore,
            presentOutput: presentOutput,
            applicationLauncher: applicationLauncher
        )
        return ExecutionTestContext(
            directory: directory,
            store: store,
            logStore: logStore,
            shortcut: shortcut,
            executor: executor
        )
    }
}

@MainActor
private struct ExecutionTestContext {
    let directory: URL
    let store: ShortcutStore
    let logStore: ScriptLogStore
    let shortcut: Shortcut
    let executor: ShortcutExecutor

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class TestScriptPresentationRecorder {
    var logs: [ScriptExecutionLog] = []
}

private final class TestRunningApplication {
    let activationPolicy: NSApplication.ActivationPolicy
    let activationResult: Bool
    let hideResult: Bool
    let isActive: Bool

    private(set) var didHide = false
    private(set) var didUnhide = false
    private(set) var activationOptions: NSApplication.ActivationOptions?

    init(
        activationPolicy: NSApplication.ActivationPolicy,
        isActive: Bool = false,
        hideResult: Bool = true,
        activationResult: Bool = true
    ) {
        self.activationPolicy = activationPolicy
        self.isActive = isActive
        self.hideResult = hideResult
        self.activationResult = activationResult
    }

    var handle: RunningApplicationHandle {
        RunningApplicationHandle(
            activationPolicy: activationPolicy,
            isActive: isActive,
            hide: { [self] in
                didHide = true
                return hideResult
            },
            unhide: { [self] in
                didUnhide = true
            },
            activate: { [self] options in
                activationOptions = options
                return activationResult
            }
        )
    }
}
