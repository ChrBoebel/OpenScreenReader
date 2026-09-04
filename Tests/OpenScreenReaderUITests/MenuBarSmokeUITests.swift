import XCTest

final class MenuBarSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarShellExposesCurrentStatusAndActions() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }

        let statusItem = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Ready'"))
            .firstMatch

        XCTAssertTrue(
            statusItem.waitForExistence(timeout: 5),
            "Expected the OpenScreenReader menu bar item to be accessible."
        )
        statusItem.click()

        XCTAssertTrue(app.menuItems["Ready"].waitForExistence(timeout: 2))

        let readRegion = app.menuItems["Read Screen Region…"]
        XCTAssertTrue(readRegion.exists)
        XCTAssertTrue(readRegion.isEnabled)

        XCTAssertTrue(
            app.menuItems[
                "Select a region to recognize text locally. Speech is not available yet."
            ].exists
        )
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        XCTAssertTrue(app.menuItems["Quit OpenScreenReader"].exists)

        readRegion.click()

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "The menu action did not expose the selection overlay.\n\(statusDescription(in: app))"
        )

        app.typeKey(.escape, modifierFlags: [])

        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Stopped'"))
            .firstMatch
        XCTAssertTrue(stoppedStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    func testDraggingARegionReportsCaptureOrActionablePermissionFailure() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }

        openMenu(in: app, status: "Ready")
        app.menuItems["Read Screen Region…"].click()

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "Expected an accessible selection overlay.\n\(statusDescription(in: app))"
        )

        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        let end = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)

        let finishedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title IN {'OpenScreenReader, Ready', 'OpenScreenReader, Error'}"))
            .firstMatch
        XCTAssertTrue(finishedStatus.waitForExistence(timeout: 17), statusDescription(in: app))
        let failed = finishedStatus.title == "OpenScreenReader, Error"
        finishedStatus.click()
        if failed {
            let permissionError = app.menuItems.matching(NSPredicate(
                format: "title CONTAINS 'Allow Input Monitoring' OR title CONTAINS 'Allow Screen Recording'"
            )).firstMatch
            XCTAssertTrue(permissionError.waitForExistence(timeout: 2), statusDescription(in: app))
        } else {
            let recognitionResult = app.menuItems.matching(NSPredicate(
                format: "title BEGINSWITH 'Recognized ' OR title == 'No readable text found. Select a clearer region.'"
            )).firstMatch
            XCTAssertTrue(recognitionResult.waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testSettingsExplainCapturePrivacyAndPermissionActions() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        XCTAssertTrue(app.buttons["Allow Screen Recording…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Allow Input Monitoring…"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'Only the selected region'"
        )).firstMatch.exists)
    }

    @MainActor
    func testCustomShortcutPersistsAndStartsAndCancelsFromFinder() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        let key = app.popUpButtons["shortcutKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 3))
        key.click()
        app.menuItems["J"].click()
        app.buttons["applyShortcut"].click()
        XCTAssertTrue(app.staticTexts["Shortcut ⌘⇧J is active and saved."].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        XCTAssertTrue(app.popUpButtons["shortcutKey"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.popUpButtons["shortcutKey"].value as? String, "J")

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("j", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.groups["Screen region selection"].firstMatch.waitForExistence(timeout: 3))
        finder.activate()
        finder.typeKey("j", modifierFlags: [.command, .shift])
        openMenu(in: app, status: "Stopped")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        app.buttons["Restore Default"].click()
        XCTAssertTrue(app.staticTexts["Shortcut ⌘⇧Y is active and saved."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testShortcutValidationAndCommonCommandWarning() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        XCTAssertTrue(app.checkBoxes["Command ⌘"].waitForExistence(timeout: 3))
        app.checkBoxes["Command ⌘"].click()
        XCTAssertFalse(app.buttons["applyShortcut"].isEnabled)
        app.checkBoxes["Command ⌘"].click()
        app.checkBoxes["Shift ⇧"].click()
        app.buttons["applyShortcut"].click()
        XCTAssertTrue(app.buttons["Use Shortcut"].waitForExistence(timeout: 3))
        app.sheets.buttons["Cancel"].click()
        XCTAssertFalse(app.staticTexts["Shortcut ⌘Y is active and saved."].exists)
        app.buttons["Restore Default"].click()
        XCTAssertTrue(app.staticTexts["Shortcut ⌘⇧Y is active and saved."].waitForExistence(timeout: 3))
    }

    @MainActor
    private func makeApplication() -> XCUIApplication {
        let suite = "com.christopherbobel.OpenScreenReader.uitests.\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["OSR_SHORTCUT_TEST_SUITE"] = suite
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return app
    }

    @MainActor
    func testGlobalHotkeyStartsAndRepeatedHotkeyCancelsFromFinder() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }

        let readyStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Ready'"))
            .firstMatch
        XCTAssertTrue(readyStatus.waitForExistence(timeout: 5))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("y", modifierFlags: [.command, .shift])

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "Expected the global hotkey to expose the selection overlay.\n\(statusDescription(in: app))"
        )

        finder.activate()
        finder.typeKey("y", modifierFlags: [.command, .shift])

        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'OpenScreenReader, Stopped'"))
            .firstMatch
        XCTAssertTrue(stoppedStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    private func statusDescription(in app: XCUIApplication) -> String {
        // Do not include the application's Apple menu and private Recent Items.
        app.descendants(matching: .statusItem).debugDescription
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
