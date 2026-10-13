import AppKit
import XCTest

final class MenuBarSmokeUITests: XCTestCase {
    @MainActor
    func testReadingSpeedPersistsAndQueueActionsAreAvailable() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        let status = app.descendants(matching: .statusItem).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.click()
        // Playback controls appear only while something is reading.
        XCTAssertTrue(app.menuItems["Read Screen Region…"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.menuItems["Add Screen Region to Queue…"].exists)
        XCTAssertFalse(app.menuItems["Next Text"].exists)
        // macOS can expose an infinite frame for SettingsLink inside a status
        // menu. Exercise the native Settings command instead of guessed points.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(",", modifierFlags: [.command])
        openSettingsTab("Read Aloud", in: app)
        let speed = app.popUpButtons["readingSpeed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        speed.click()
        speed.menuItems["1.5×"].click()
        expectation(for: NSPredicate(format: "value == %@", "1.5×"), evaluatedWith: speed)
        waitForExpectations(timeout: 3)
        app.terminate()
        app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.click()
        XCTAssertTrue(app.menuItems["Speed · 1.5×"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(",", modifierFlags: [.command])
        openSettingsTab("Read Aloud", in: app)
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        XCTAssertEqual(speed.value as? String, "1.5×")
        // The separate Add shortcut starts a selection when idle. No capture
        // permission is required until the user actually commits a region.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("y", modifierFlags: [.command, .option, .shift])
        XCTAssertTrue(app.groups["Screen region selection"].firstMatch.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Stopped'"))
            .firstMatch.waitForExistence(timeout: 3))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarShellExposesCurrentStatusAndActions() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }

        let statusItem = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Ready'"))
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

        XCTAssertTrue(app.menuItems["Settings…"].exists)
        XCTAssertTrue(app.menuItems["Quit Saywing"].exists)

        readRegion.click()

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "The menu action did not expose the selection overlay.\n\(statusDescription(in: app))"
        )

        app.typeKey(.escape, modifierFlags: [])

        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Stopped'"))
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
            .matching(NSPredicate(format: "title IN {'Saywing, Ready', 'Saywing, Error', 'Saywing, Preparing voice', 'Saywing, Speaking'}"))
            .firstMatch
        XCTAssertTrue(finishedStatus.waitForExistence(timeout: 17), statusDescription(in: app))
        let failed = finishedStatus.title == "Saywing, Error"
        let reading = finishedStatus.title == "Saywing, Preparing voice" || finishedStatus.title == "Saywing, Speaking"
        finishedStatus.click()
        if reading {
            XCTAssertTrue(app.menuItems["Stop Reading"].exists)
            app.menuItems["Stop Reading"].click()
        } else if failed {
            let permissionError = app.menuItems.matching(NSPredicate(
                format: "title CONTAINS 'Allow Input Monitoring' OR title CONTAINS 'Allow Screen Recording' OR title CONTAINS 'local Supertonic development runtime is not installed'"
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
        // Settings and branding must remain available even when this machine
        // cannot register the global shortcut. Pipeline tests still require Ready.
        let status = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title BEGINSWITH 'Saywing, '")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), statusDescription(in: app))
        status.click()
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("General", in: app)
        XCTAssertTrue(app.images["Saywing Quiet Owl app logo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Read aloud and dictate on your Mac."].exists)
        openSettingsTab("Privacy", in: app)
        for permission in ["Screen Recording", "Input Monitoring", "Microphone", "Accessibility"] {
            XCTAssertTrue(app.staticTexts[permission].waitForExistence(timeout: 3), permission)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'never saved'"
        )).firstMatch.exists)
        let preview = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        preview.name = "Saywing-settings"
        preview.lifetime = .keepAlways
        add(preview)
    }

    @MainActor
    func testInterfaceSoundsPreferencePersists() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        let sounds = app.checkBoxes["interfaceSoundsEnabled"]
        XCTAssertTrue(sounds.waitForExistence(timeout: 3))
        XCTAssertEqual((sounds.value as? NSNumber)?.boolValue ?? ((sounds.value as? String) == "1"), true, sounds.debugDescription)
        sounds.click()
        XCTAssertEqual((sounds.value as? NSNumber)?.boolValue ?? ((sounds.value as? String) != "0"), false, sounds.debugDescription)
        app.terminate()
        app.launch()
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        XCTAssertTrue(sounds.waitForExistence(timeout: 3))
        XCTAssertEqual((sounds.value as? NSNumber)?.boolValue ?? ((sounds.value as? String) != "0"), false, sounds.debugDescription)
    }

    @MainActor
    func testControlCanDockOnBothSidesAndRememberDraggedPosition() throws {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Read Aloud", in: app)
        let preview = app.buttons["previewReadingPanelPosition"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.click()
        let control = app.groups["readingStatusContent"]
        XCTAssertTrue(control.waitForExistence(timeout: 3))
        let screen = try XCTUnwrap(NSScreen.main)
        let height = screen.frame.height
        let visible = screen.visibleFrame
        let initial = control.frame
        let center = control.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5))
        let left = center.withOffset(CGVector(dx: visible.minX + 40 - (initial.minX + initial.width * 0.42),
                                              dy: height - visible.midY - initial.midY))
        center.press(forDuration: 0.1, thenDragTo: left)
        let vertical = NSPredicate { _, _ in control.frame.height > control.frame.width }
        expectation(for: vertical, evaluatedWith: control)
        waitForExpectations(timeout: 3)
        XCTAssertLessThan(control.frame.midX, visible.minX + 100)
        // AppKit expands this borderless NSButton's accessibility frame by
        // 1 pt on each side (44 pt view → 46 pt AX frame). The native view
        // tests assert exact geometry; here verify the accessible hit target.
        let stopFrame = app.buttons["readingStatusAction"].frame
        XCTAssertGreaterThanOrEqual(stopFrame.width, 44)
        XCTAssertGreaterThanOrEqual(stopFrame.height, 44)
        let side = control.frame
        let grip = control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let right = grip.withOffset(CGVector(dx: visible.maxX - 40 - side.midX, dy: 0))
        grip.press(forDuration: 0.1, thenDragTo: right)
        expectation(for: NSPredicate { _, _ in control.frame.midX > visible.maxX - 100 }, evaluatedWith: control)
        waitForExpectations(timeout: 3)
        // Wait for the bounded snap to finish before comparing restored coordinates.
        let docked = NSPredicate { _, _ in abs(control.frame.maxX - (visible.maxX - 4)) < 1 }
        expectation(for: docked, evaluatedWith: control)
        waitForExpectations(timeout: 3)
        let saved = control.frame
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Right-edge vertical control"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["readingStatusAction"].click()
        expectation(for: NSPredicate { _, _ in !control.exists }, evaluatedWith: control)
        waitForExpectations(timeout: 3)
        app.terminate()
        app.launch()
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Read Aloud", in: app)
        preview.click()
        XCTAssertTrue(control.waitForExistence(timeout: 3))
        XCTAssertEqual(control.frame, saved)
        let restoredGrip = control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let bottom = restoredGrip.withOffset(CGVector(dx: visible.midX - control.frame.midX,
            dy: height - visible.minY - 45 - (control.frame.minY + control.frame.height * 0.42)))
        restoredGrip.press(forDuration: 0.1, thenDragTo: bottom)
        expectation(for: NSPredicate { _, _ in control.frame.width > control.frame.height }, evaluatedWith: control)
        waitForExpectations(timeout: 3)
        let picker = app.popUpButtons["readingPanelPosition"]
        picker.click()
        picker.menuItems["Left"].firstMatch.click()
        expectation(for: NSPredicate { _, _ in control.frame.height > control.frame.width && control.frame.midX < visible.minX + 100 },
                    evaluatedWith: control)
        waitForExpectations(timeout: 3)
        app.buttons["readingStatusAction"].click()
    }

    @MainActor
    func testLocalSupertonicReadsFixtureAndEscapeStopsIt() throws {
        try verifyLocalSupertonic(ending: .escape)
    }

    @MainActor
    func testLocalSupertonicReadsFixtureAndRepeatedShortcutOpensAdditionalSelection() throws {
        try verifyLocalSupertonic(ending: .shortcut)
    }

    @MainActor
    func testReadingPanelStopButtonPreservesOtherAppFocus() throws {
        try verifyLocalSupertonic(ending: .panel)
    }

    @MainActor
    func testReadingPanelDisappearsAfterNaturalCompletion() throws {
        try verifyLocalSupertonic(ending: .complete)
    }

    private enum ReadingEnd { case escape, shortcut, panel, complete }

    @MainActor
    private func verifyLocalSupertonic(ending: ReadingEnd) throws {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Read Aloud", in: app)
        XCTAssertTrue(app.popUpButtons["readingSpeed"].waitForExistence(timeout: 5))
        try XCTSkipUnless(app.staticTexts["Installed for local development"].exists,
                          "Install the pinned development runtime for this real Supertonic test.")
        XCTAssertTrue(app.staticTexts["Supertonic 3 · M1"].exists)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = XCUIApplication(url: repository.appendingPathComponent(".build/SpeechFixture.app"))
        fixture.launch()
        defer { fixture.terminate() }
        let fixtureText = fixture.staticTexts["speechFixtureText"]
        XCTAssertTrue(fixtureText.waitForExistence(timeout: 5))
        let region = fixtureText.frame.insetBy(dx: -5, dy: -4)
        XCTAssertTrue(region.width > 0 && region.height > 0 && region.minX.isFinite && region.minY.isFinite)
        // Start through the menu so this test isolates OCR/speech and its
        // global stop paths from the separate hotkey-start delivery checks.
        openMenu(in: app, status: "Ready")
        app.menuItems["Read Screen Region…"].click()
        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), statusDescription(in: app))
        XCTAssertFalse(app.buttons["readingStatusAction"].exists, "The panel must not cover the selected image.")
        let origin = overlay.coordinate(withNormalizedOffset: .zero)
        let frame = overlay.frame
        let start = origin.withOffset(CGVector(dx: region.minX - frame.minX, dy: region.minY - frame.minY))
        let end = origin.withOffset(CGVector(dx: region.maxX - frame.minX, dy: region.maxY - frame.minY))
        start.press(forDuration: 0.1, thenDragTo: end)
        fixture.activate()
        let speaking = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Speaking'")).firstMatch
        XCTAssertTrue(speaking.waitForExistence(timeout: 90), statusDescription(in: app))
        let action = app.buttons["readingStatusAction"]
        if !action.waitForExistence(timeout: 3) {
            let dialog = app.dialogs.firstMatch
            if dialog.exists {
                let attachment = XCTAttachment(screenshot: dialog.screenshot())
                attachment.name = "reading-panel-missing-action"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTFail(app.dialogs.debugDescription)
            return
        }
        XCTAssertEqual(action.label, "Stop reading")
        XCTAssertGreaterThanOrEqual(action.frame.width, 44)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        XCTAssertEqual(fixture.state, .runningForeground, "Showing and updating the panel must not activate OpenScreenReader.")
        if ending == .complete {
            let ready = app.descendants(matching: .statusItem)
                .matching(NSPredicate(format: "title == 'Saywing, Ready'")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 30), statusDescription(in: app))
            XCTAssertTrue(action.waitForNonExistence(timeout: 4))
            XCTAssertEqual(fixture.state, .runningForeground,
                "Foreground application after completion: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
            return
        }
        if ending == .panel {
            let panel = app.groups["readingStatusContent"].firstMatch
            XCTAssertTrue(panel.exists, app.debugDescription)
            let attachment = XCTAttachment(screenshot: panel.screenshot())
            attachment.name = "reading-panel-speaking"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Click the observed button coordinates from the foreground fixture;
            // do not let XCTest activate the background app before the click.
            let target = action.frame
            let fixtureFrame = fixtureText.frame
            XCTAssertTrue([target.midX, target.midY, fixtureFrame.minX, fixtureFrame.minY].allSatisfy(\.isFinite))
            fixtureText.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: target.midX - fixtureFrame.minX, dy: target.midY - fixtureFrame.minY)
            ).click()
            XCTAssertEqual(fixture.state, .runningForeground, "Stopping must leave the user's document active.")
        } else {
            let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
            finder.activate()
            if ending == .shortcut {
                finder.typeKey("r", modifierFlags: [.option])
                XCTAssertTrue(app.groups["Screen region selection"].firstMatch.waitForExistence(timeout: 3))
                app.typeKey(.escape, modifierFlags: [])
            }
            else { finder.typeKey(.escape, modifierFlags: []) }
        }
        let stopped = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Stopped'")).firstMatch
        XCTAssertTrue(stopped.waitForExistence(timeout: 3), statusDescription(in: app))
        XCTAssertTrue(action.waitForNonExistence(timeout: 4), "The stopped panel should disappear automatically.")
    }

    @MainActor
    func testCustomShortcutPersistsAndStartsAndCancelsFromFinder() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Shortcuts", in: app)
        let recorder = app.buttons["shortcutRecorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        recorder.click()
        app.typeKey("j", modifierFlags: [.option])
        XCTAssertTrue(app.staticTexts["Shortcut ⌥J is active and saved."].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Shortcuts", in: app)
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        XCTAssertEqual(recorder.value as? String, "⌥J")

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("j", modifierFlags: [.option])
        XCTAssertTrue(app.groups["Screen region selection"].firstMatch.waitForExistence(timeout: 3))
        app.typeKey("j", modifierFlags: [.option])
        XCTAssertTrue(app.groups["Screen region selection"].firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        openMenu(in: app, status: "Stopped")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Shortcuts", in: app)
        app.buttons["Restore Default"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Shortcut ⌥R is active and saved."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testShortcutValidationAndCommonCommandWarning() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }
        openMenu(in: app, status: "Ready")
        app.descendants(matching: .statusItem).menuItems["Settings…"].firstMatch.click()
        openSettingsTab("Shortcuts", in: app)
        let recorder = app.buttons["shortcutRecorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        recorder.click()
        app.typeKey("r", modifierFlags: [.shift])
        XCTAssertTrue(app.staticTexts["Use a letter, digit or Space with ⌘, ⌥ or ⌃. Shift is optional."]
            .waitForExistence(timeout: 3))
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(app.buttons["Use Shortcut"].waitForExistence(timeout: 3))
        app.sheets.buttons["Cancel"].click()
        XCTAssertFalse(app.staticTexts["Shortcut ⌘R is active and saved."].exists)
        XCTAssertEqual(recorder.value as? String, "⌥R")
    }

    @MainActor
    private func makeApplication() -> XCUIApplication {
        let suite = "com.christopherbobel.OpenScreenReader.uitests.\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["OSR_SHORTCUT_TEST_SUITE"] = suite
        // Assertions use the English source strings; the German catalog has its own checks.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return app
    }

    @MainActor
    func testGlobalHotkeyKeepsExistingSelectionAndEscapeCancels() {
        let app = makeApplication()
        app.launch()
        defer { app.terminate() }

        let readyStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Ready'"))
            .firstMatch
        XCTAssertTrue(readyStatus.waitForExistence(timeout: 5))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("r", modifierFlags: [.option])

        let overlay = app.groups["Screen region selection"].firstMatch
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 2),
            "Expected the global hotkey to expose the selection overlay.\n\(statusDescription(in: app))"
        )

        // The overlay owns focus after starting. Do not activate Finder again:
        // XCTest may click through the overlay while activating another app.
        app.typeKey("r", modifierFlags: [.option])

        XCTAssertTrue(overlay.exists, statusDescription(in: app))
        app.typeKey(.escape, modifierFlags: [])
        let stoppedStatus = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, Stopped'"))
            .firstMatch
        XCTAssertTrue(stoppedStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    private func statusDescription(in app: XCUIApplication) -> String {
        // Do not include the application's Apple menu and private Recent Items.
        app.descendants(matching: .statusItem).debugDescription
    }

    @MainActor
    private func openSettingsTab(_ title: String, in app: XCUIApplication) {
        let tab = app.toolbars.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Settings tab \(title) is missing.")
        tab.click()
    }

    @MainActor
    private func openMenu(in app: XCUIApplication, status: String) {
        let statusItem = app.descendants(matching: .statusItem)
            .matching(NSPredicate(format: "title == 'Saywing, \(status)'"))
            .firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), statusDescription(in: app))
        statusItem.click()
    }
}
