import AppKit
import ScreenCaptureKit

enum ScreenCaptureFailure: Error, Equatable, LocalizedError {
    case permissionRequired
    case displayChanged
    case invalidRegion
    case failed

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Allow Screen Recording in Settings to capture the selected region."
        case .displayChanged:
            "The display layout changed. Please select the region again."
        case .invalidRegion:
            "The selected region is invalid. Please select it again."
        case .failed:
            "The region could not be captured. Check Screen Recording permission and try again."
        }
    }
}

struct RegionCaptureRequest {
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    init(selection: ScreenRegionSelection, currentDisplay: DisplaySelectionGeometry) throws {
        guard selection.displayGeometry == currentDisplay,
              selection.displayID == currentDisplay.displayID else {
            throw ScreenCaptureFailure.displayChanged
        }
        let rect = selection.rectInScreenPoints
        let scale = currentDisplay.backingScaleFactor
        guard [rect.minX, rect.minY, rect.width, rect.height, scale].allSatisfy(\.isFinite),
              scale > 0, rect.width >= 3, rect.height >= 3,
              currentDisplay.frameInScreenPoints.contains(rect) else {
            throw ScreenCaptureFailure.invalidRegion
        }
        // AppKit has a bottom-left origin; ScreenCaptureKit samples display-local
        // logical points from the top-left. Pixel dimensions are a separate concern.
        sourceRect = CGRect(
            x: rect.minX - currentDisplay.frameInScreenPoints.minX,
            y: currentDisplay.frameInScreenPoints.maxY - rect.maxY,
            width: rect.width, height: rect.height
        )
        let width = (rect.width * scale).rounded(.up)
        let height = (rect.height * scale).rounded(.up)
        guard width.isFinite, height.isFinite, width <= 32768, height <= 32768 else {
            throw ScreenCaptureFailure.invalidRegion
        }
        pixelWidth = Int(width)
        pixelHeight = Int(height)
    }

    func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        config.capturesAudio = false
        config.preservesAspectRatio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }
}

@MainActor
protocol ScreenCapturing: AnyObject {
    func capture(_ selection: ScreenRegionSelection) async throws -> CGImage
}

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    func capture(_ selection: ScreenRegionSelection) async throws -> CGImage {
        try Task.checkCancellation()
        let revision = DisplayTopology.shared.revision
        let topology = Self.currentDisplays()
        guard selection.topologyRevision == revision,
              let display = topology.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureFailure.displayChanged
        }
        let request = try RegionCaptureRequest(selection: selection, currentDisplay: display)
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureFailure.permissionRequired
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard revision == DisplayTopology.shared.revision, topology == Self.currentDisplays(),
                  let target = content.displays.first(where: { $0.displayID == selection.displayID }) else {
                throw ScreenCaptureFailure.displayChanged
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: target, excludingApplications: ownApps, exceptingWindows: [])
            if #available(macOS 14.2, *) { filter.includeMenuBar = true }
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: request.makeConfiguration()
            )
            // Apple's one-shot API cannot be interrupted. Never deliver a late frame.
            try Task.checkCancellation()
            guard revision == DisplayTopology.shared.revision, topology == Self.currentDisplays() else {
                throw ScreenCaptureFailure.displayChanged
            }
            guard image.width == request.pixelWidth, image.height == request.pixelHeight else {
                throw ScreenCaptureFailure.failed
            }
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ScreenCaptureFailure {
            throw failure
        } catch {
            // Do not forward system error payloads that could contain window metadata.
            throw ScreenCaptureFailure.failed
        }
    }

    static func currentDisplays() -> [DisplaySelectionGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplaySelectionGeometry(displayID: number.uint32Value,
                frameInScreenPoints: screen.frame, backingScaleFactor: screen.backingScaleFactor)
        }.sorted { $0.displayID < $1.displayID }
    }
}
