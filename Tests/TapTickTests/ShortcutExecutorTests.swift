import AppKit
import Testing
@testable import TapTickKit

@MainActor
@Suite("ShortcutExecutor")
struct ShortcutExecutorTests {
    @Test("Launch app focuses an activatable running instance")
    func focusesRunningApplication() {
        let app = TestRunningApplication(activationPolicy: .regular)
        var openedURL: URL?

        let executor = ShortcutExecutor(
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [app.handle] },
                applicationURL: { _ in URL(fileURLWithPath: "/Applications/Test.app") },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )

        executor.execute(action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"))

        #expect(app.didUnhide)
        #expect(app.activationOptions == [.activateAllWindows])
        #expect(openedURL == nil)
    }

    @Test("Launch app falls back to Launch Services when only helpers are running")
    func launchesWhenOnlyHelpersExist() {
        let helper = TestRunningApplication(activationPolicy: .prohibited)
        let expectedURL = URL(fileURLWithPath: "/Applications/Test.app")
        var openedURL: URL?

        let executor = ShortcutExecutor(
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [helper.handle] },
                applicationURL: { _ in expectedURL },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )

        executor.execute(action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"))

        #expect(helper.didUnhide == false)
        #expect(helper.activationOptions == nil)
        #expect(openedURL == expectedURL)
    }

    @Test("Launch app falls back to Launch Services when activation fails")
    func relaunchesWhenActivationFails() {
        let app = TestRunningApplication(activationPolicy: .regular, activationResult: false)
        let expectedURL = URL(fileURLWithPath: "/Applications/Test.app")
        var openedURL: URL?

        let executor = ShortcutExecutor(
            applicationLauncher: ApplicationLauncher(
                runningApplications: { _ in [app.handle] },
                applicationURL: { _ in expectedURL },
                openApplication: { url, completion in
                    openedURL = url
                    completion(nil)
                }
            )
        )

        executor.execute(action: .launchApp(bundleIdentifier: "com.test.app", appName: "Test"))

        #expect(app.didUnhide)
        #expect(app.activationOptions == [.activateAllWindows])
        #expect(openedURL == expectedURL)
    }
}

private final class TestRunningApplication {
    let activationPolicy: NSApplication.ActivationPolicy
    let activationResult: Bool

    private(set) var didUnhide = false
    private(set) var activationOptions: NSApplication.ActivationOptions?

    init(
        activationPolicy: NSApplication.ActivationPolicy,
        activationResult: Bool = true
    ) {
        self.activationPolicy = activationPolicy
        self.activationResult = activationResult
    }

    var handle: RunningApplicationHandle {
        RunningApplicationHandle(
            activationPolicy: activationPolicy,
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
