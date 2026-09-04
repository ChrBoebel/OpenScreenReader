import AppKit
import Testing
@testable import OpenScreenReader

@Suite("Selected region capture")
@MainActor
struct CaptureTests {
    @Test
    func captureCoordinatesFlipVerticallyAndUseDisplayLocalPoints() throws {
        let display = DisplaySelectionGeometry(
            displayID: 9,
            frameInScreenPoints: CGRect(x: -1440, y: 100, width: 1440, height: 900),
            backingScaleFactor: 2
        )
        let selection = try #require(display.selection(
            from: CGPoint(x: 100, y: 200), to: CGPoint(x: 500, y: 350)
        ))
        let request = try RegionCaptureRequest(selection: selection, currentDisplay: display)
        #expect(request.sourceRect == CGRect(x: 100, y: 550, width: 400, height: 150))
        #expect(request.pixelWidth == 800)
        #expect(request.pixelHeight == 300)
    }

    @Test
    func changedDisplayGeometryIsRejected() throws {
        let original = DisplaySelectionGeometry(
            displayID: 9, frameInScreenPoints: CGRect(x: 0, y: 0, width: 1000, height: 700),
            backingScaleFactor: 2
        )
        let selection = try #require(original.selection(
            from: CGPoint(x: 10, y: 20), to: CGPoint(x: 200, y: 100)
        ))
        let moved = DisplaySelectionGeometry(
            displayID: 9, frameInScreenPoints: CGRect(x: 100, y: 0, width: 1000, height: 700),
            backingScaleFactor: 2
        )
        #expect(throws: ScreenCaptureFailure.displayChanged) {
            try RegionCaptureRequest(selection: selection, currentDisplay: moved)
        }
    }

    @Test
    func captureConfigurationExcludesCursorAudioAndScalesWithoutPadding() throws {
        let display = DisplaySelectionGeometry(
            displayID: 1, frameInScreenPoints: CGRect(x: 0, y: 0, width: 1000, height: 700),
            backingScaleFactor: 2
        )
        let selection = try #require(display.selection(
            from: CGPoint(x: 20, y: 30), to: CGPoint(x: 220, y: 130)
        ))
        let request = try RegionCaptureRequest(selection: selection, currentDisplay: display)
        let config = request.makeConfiguration()
        #expect(config.sourceRect == request.sourceRect)
        #expect(config.width == 400 && config.height == 200)
        #expect(!config.showsCursor)
        #expect(!config.capturesAudio)
        #expect(!config.preservesAspectRatio)
    }
}
