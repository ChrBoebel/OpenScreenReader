import CoreGraphics
import Testing
@testable import OpenScreenReader

@Suite("Primary interaction")
@MainActor
struct InteractionTests {
    @Test
    func defaultShortcutIsExplicitAndReadable() {
        #expect(HotkeyShortcut.readScreenRegion.keyCode == 15)
        #expect(HotkeyShortcut.readScreenRegion.displayName == "⌃⌥R")
    }

    @Test
    func appRegistersTheHotkeyAndStartsSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .registered)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection)

        #expect(hotkey.registeredShortcut == .readScreenRegion)
        #expect(model.hotkeyRegistration == .registered)

        await model.handleReadRequest()

        #expect(model.status == .selecting)
        #expect(selection.startCount == 1)
        #expect(selection.cancelCount == 0)
    }

    @Test
    func repeatedReadRequestCancelsTheActiveSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .registered)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection)

        await model.handleReadRequest()
        await model.handleReadRequest()

        let snapshot = await model.pipelineCoordinator.snapshot()
        #expect(model.status == .stopped)
        #expect(selection.cancelCount == 1)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.pendingCancellation == nil)
    }

    @Test
    func completedSelectionIsPublishedWithoutPersistingPixels() async {
        let selection = RegionSelectionControllerFake()
        let model = AppModel(
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection
        )
        let region = ScreenRegionSelection(
            displayID: 7,
            rectInScreenPoints: CGRect(x: 100, y: 80, width: 400, height: 220),
            rectInBackingPixels: CGRect(x: 200, y: 160, width: 800, height: 440),
            backingScaleFactor: 2
        )

        await model.handleReadRequest()
        selection.complete(region)
        await model.waitForInteractionToSettle()

        let snapshot = await model.pipelineCoordinator.snapshot()
        #expect(model.lastSelection == region)
        #expect(model.status == .ready)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.lastTerminal?.reason == .completed)
    }

    @Test
    func registrationConflictIsVisibleAndPreventsSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .conflict)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection)

        await model.handleReadRequest()

        #expect(model.hotkeyRegistration == .conflict)
        #expect(model.status == .error)
        #expect(selection.startCount == 0)
    }

    @Test
    func selectionGeometryHandlesNegativeDisplayOriginsAndRetinaScale() throws {
        let geometry = DisplaySelectionGeometry(
            displayID: 9,
            frameInScreenPoints: CGRect(x: -1440, y: 100, width: 1440, height: 900),
            backingScaleFactor: 2
        )

        let selection = try #require(
            geometry.selection(
                from: CGPoint(x: 500, y: 350),
                to: CGPoint(x: 100, y: 200)
            )
        )

        #expect(selection.displayID == 9)
        #expect(selection.rectInScreenPoints == CGRect(x: -1340, y: 300, width: 400, height: 150))
        #expect(selection.rectInBackingPixels == CGRect(x: 200, y: 400, width: 800, height: 300))
        #expect(selection.backingScaleFactor == 2)
    }

    @Test
    func selectionGeometryClipsToItsStartDisplayAndRejectsZeroArea() {
        let geometry = DisplaySelectionGeometry(
            displayID: 3,
            frameInScreenPoints: CGRect(x: 0, y: 0, width: 1000, height: 700),
            backingScaleFactor: 1
        )

        let clipped = geometry.selection(
            from: CGPoint(x: 900, y: 600),
            to: CGPoint(x: 1200, y: 900)
        )

        #expect(clipped?.rectInScreenPoints == CGRect(x: 900, y: 600, width: 100, height: 100))
        #expect(geometry.selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11)) == nil)
    }
}

@MainActor
private final class HotkeyManagerFake: HotkeyManaging {
    var onPress: (() -> Void)?
    private(set) var registeredShortcut: HotkeyShortcut?
    private let registrationResult: HotkeyRegistration

    init(registrationResult: HotkeyRegistration) {
        self.registrationResult = registrationResult
    }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        registeredShortcut = shortcut
        return registrationResult
    }

    func unregister() {}
}

@MainActor
private final class RegionSelectionControllerFake: RegionSelectionControlling {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var completion: ((ScreenRegionSelection) -> Void)?

    func start(
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        startCount += 1
        completion = onSelection
    }

    func cancel() {
        cancelCount += 1
        completion = nil
    }

    func complete(_ selection: ScreenRegionSelection) {
        let completion = completion
        self.completion = nil
        completion?(selection)
    }
}
