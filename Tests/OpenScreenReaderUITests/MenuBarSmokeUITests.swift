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
        XCTAssertTrue(readRegion.isEnabled)

        XCTAssertTrue(
            app.menuItems[
                "Select a region to capture locally. Speech is not available yet."
            ].exists
        )
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        XCTAssertTrue(app.menuItems["Quit OpenScreenReader"].exists)

        readRegion.click()

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "The global shortcut did not expose the selection overlay.\n\(app.debugDescription)"
        )

        app.typeKey(.escape, modifierFlags: [])

        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Stopped'"))
            .firstMatch
        XCTAssertTrue(stoppedStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    func testDraggingARegionReportsCaptureOrActionablePermissionFailure() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        openMenu(in: app, status: "Ready")
        app.menuItems["Read Screen Region…"].click()

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "Expected an accessible selection overlay.\n\(app.debugDescription)"
        )

        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        let end = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)

        let finishedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title IN {'OpenScreenReader, Ready', 'OpenScreenReader, Error'}"))
            .firstMatch
        XCTAssertTrue(finishedStatus.waitForExistence(timeout: 12))
        let failed = finishedStatus.title == "OpenScreenReader, Error"
        finishedStatus.click()
        if failed {
            let permissionError = app.menuItems.matching(NSPredicate(
                format: "title CONTAINS 'Allow Input Monitoring' OR title CONTAINS 'Allow Screen Recording'"
            )).firstMatch
            XCTAssertTrue(permissionError.waitForExistence(timeout: 2), app.debugDescription)
        } else {
            XCTAssertTrue(app.menuItems["Region captured locally. No image was saved."].waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testSettingsExplainCapturePrivacyAndPermissionActions() {
        let app = XCUIApplication()
        app.launch()
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        XCTAssertTrue(app.buttons["Allow Screen Recording…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Allow Input Monitoring…"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'Only the selected region'"
        )).firstMatch.exists)
    }

    @MainActor
    func testGlobalHotkeyStartsAndRepeatedHotkeyCancelsFromFinder() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let readyStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Ready'"))
            .firstMatch
        XCTAssertTrue(readyStatus.waitForExistence(timeout: 5))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("r", modifierFlags: [.control, .option])

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "Expected the global hotkey to expose the selection overlay.\n\(app.debugDescription)"
        )

        finder.activate()
        finder.typeKey("r", modifierFlags: [.control, .option])

        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Stopped'"))
            .firstMatch
        XCTAssertTrue(stoppedStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    private func openMenu(in app: XCUIApplication, status: String) {
        let statusItem = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, \(status)'"))
            .firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
    }
}
