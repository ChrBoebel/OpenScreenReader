import XCTest

final class MenuBarSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarShellExposesCurrentStatusAndActions() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let statusItem = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Ready'"))
            .firstMatch

        XCTAssertTrue(
            statusItem.waitForExistence(timeout: 5),
            "Expected the OpenScreenReader menu bar item to be accessible.\n\(app.debugDescription)"
        )
        statusItem.click()

        XCTAssertTrue(app.menuItems["Ready"].waitForExistence(timeout: 2))

        let readRegion = app.menuItems["Read Screen Region…"]
        XCTAssertTrue(readRegion.exists)
        XCTAssertFalse(readRegion.isEnabled)

        XCTAssertTrue(app.menuItems["Capture is coming in the next implementation step."].exists)
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        XCTAssertTrue(app.menuItems["Quit OpenScreenReader"].exists)
    }
}
