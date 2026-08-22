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

    // MARK: - Menu Bar

    func testAppLaunches() throws {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.exists, "App should launch successfully")
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasLaunchedBefore", "YES"]
        app.launch()
        return app
    }
}
