import XCTest

@MainActor
final class TapTickUITests: XCTestCase {
    // MARK: - Settings Window

    func testSettingsWindowOpens() throws {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 5),
            "A manual launch should open the settings window"
        )
    }

    func testApplicationsPageIsSelectedByDefault() throws {
        let app = launchApp()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(
            window.searchFields["Search"].waitForExistence(timeout: 5),
            "The default Applications page should expose its search field"
        )
    }

    func testSettingsSidebarToggleWorks() throws {
        let app = launchApp()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let sidebarToggle = window.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Sidebar")
        ).firstMatch
        XCTAssertTrue(
            sidebarToggle.waitForExistence(timeout: 3),
            "Settings should expose the native sidebar toggle"
        )

        sidebarToggle.click()
        XCTAssertTrue(
            window.buttons["Show Sidebar"].waitForExistence(timeout: 3),
            "The native toggle should collapse the Settings sidebar"
        )
    }

    func testCanNavigateToGeneralSettings() throws {
        let app = launchApp()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let generalTab = window.staticTexts["General"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3))
        generalTab.click()

        XCTAssertTrue(
            window.staticTexts["Startup & Appearance"].waitForExistence(timeout: 3),
            "Selecting General should show startup settings"
        )
    }

    func testEscapeDismissesSettingsWithoutQuitting() throws {
        let app = launchApp()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])

        let windowDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: window
        )
        XCTAssertEqual(XCTWaiter.wait(for: [windowDismissed], timeout: 3), .completed)
        XCTAssertTrue(app.exists, "Dismissing Settings should keep the menu-bar app running")

        let appMovedToBackground = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.state == .runningBackground },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [appMovedToBackground], timeout: 3),
            .completed,
            "Dismissing Settings should return focus to the previous app"
        )

        app.activate()
        XCTAssertTrue(
            window.waitForExistence(timeout: 3),
            "Activating TapTick with no visible window should reopen Settings"
        )
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasLaunchedBefore", "YES",
            "-showDockIcon", "YES",
            "-showMenuBarIcon", "YES",
        ]
        app.launch()
        return app
    }
}
