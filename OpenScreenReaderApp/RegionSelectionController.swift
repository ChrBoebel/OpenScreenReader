import AppKit
import CoreGraphics

struct ScreenRegionSelection: Equatable, Sendable {
    let displayID: UInt32
    let rectInScreenPoints: CGRect
    let rectInBackingPixels: CGRect
    let backingScaleFactor: CGFloat
    var displayGeometry: DisplaySelectionGeometry? = nil
}

struct DisplaySelectionGeometry: Equatable, Sendable {
    let displayID: UInt32
    let frameInScreenPoints: CGRect
    let backingScaleFactor: CGFloat

    var localBounds: CGRect {
        CGRect(origin: .zero, size: frameInScreenPoints.size)
    }

    func selection(from start: CGPoint, to end: CGPoint) -> ScreenRegionSelection? {
        let localRect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).intersection(localBounds)

        guard localRect.width >= 3, localRect.height >= 3 else {
            return nil
        }

        return ScreenRegionSelection(
            displayID: displayID,
            rectInScreenPoints: localRect.offsetBy(
                dx: frameInScreenPoints.minX,
                dy: frameInScreenPoints.minY
            ),
            rectInBackingPixels: CGRect(
                x: localRect.minX * backingScaleFactor,
                y: localRect.minY * backingScaleFactor,
                width: localRect.width * backingScaleFactor,
                height: localRect.height * backingScaleFactor
            ),
            backingScaleFactor: backingScaleFactor,
            displayGeometry: self
        )
    }
}

@MainActor
protocol RegionSelectionControlling: AnyObject {
    func start(
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    )

    func cancel()
}

@MainActor
final class RegionSelectionOverlayController: NSObject, RegionSelectionControlling {
    private var panels: [SelectionOverlayPanel] = []
    private var onSelection: ((ScreenRegionSelection) -> Void)?
    private var onCancel: (() -> Void)?
    private var cursorIsPushed = false

    func start(
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        cancel()
        self.onSelection = onSelection
        self.onCancel = onCancel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        panels = NSScreen.screens.compactMap { screen in
            SelectionOverlayPanel(
                screen: screen,
                onSelection: { [weak self] selection in
                    self?.finish(with: selection)
                },
                onCancel: { [weak self] in
                    self?.finishAsCancelled()
                }
            )
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panels.forEach { $0.orderFrontRegardless() }
        panels.first?.makeKey()
        if !panels.isEmpty {
            NSCursor.crosshair.push()
            cursorIsPushed = true
        }
    }

    func cancel() {
        teardown()
        onSelection = nil
        onCancel = nil
    }

    private func finish(with selection: ScreenRegionSelection) {
        let completion = onSelection
        teardown()
        onSelection = nil
        onCancel = nil
        completion?(selection)
    }

    private func finishAsCancelled() {
        let cancellation = onCancel
        teardown()
        onSelection = nil
        onCancel = nil
        cancellation?()
    }

    @objc
    private func screenParametersDidChange() {
        finishAsCancelled()
    }

    private func teardown() {
        panels.forEach { $0.close() }
        panels.removeAll()
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
    }
}

@MainActor
private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(
        screen: NSScreen,
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none

        let selectionView = SelectionOverlayView(
            screen: screen,
            onSelection: onSelection,
            onCancel: onCancel
        )
        selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
        contentView = selectionView
        initialFirstResponder = selectionView
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    private let geometry: DisplaySelectionGeometry
    private let onSelection: (ScreenRegionSelection) -> Void
    private let onCancel: () -> Void
    private var dragOrigin: CGPoint?
    private var selectionRect = CGRect.zero

    override var acceptsFirstResponder: Bool { true }

    init(
        screen: NSScreen,
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let displayNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
        geometry = DisplaySelectionGeometry(
            displayID: displayNumber?.uint32Value ?? 0,
            frameInScreenPoints: screen.frame,
            backingScaleFactor: screen.backingScaleFactor
        )
        self.onSelection = onSelection
        self.onCancel = onCancel
        super.init(frame: .zero)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Screen region selection")
        setAccessibilityHelp("Drag over the text to read. Press Escape to cancel.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else {
            return
        }

        let currentPoint = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(dragOrigin.x, currentPoint.x),
            y: min(dragOrigin.y, currentPoint.y),
            width: abs(currentPoint.x - dragOrigin.x),
            height: abs(currentPoint.y - dragOrigin.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard geometry.displayID != 0,
              let dragOrigin,
              let selection = geometry.selection(
                from: dragOrigin,
                to: convert(event.locationInWindow, from: nil)
              ) else {
            onCancel()
            return
        }

        onSelection(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        context.fill(dirtyRect)

        guard !selectionRect.isEmpty else {
            return
        }

        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(selectionRect)
        context.restoreGState()

        context.setStrokeColor(NSColor(
            calibratedRed: 0x55 / 255,
            green: 0xE0 / 255,
            blue: 0xBE / 255,
            alpha: 1
        ).cgColor)
        context.setLineWidth(2)
        context.stroke(selectionRect.insetBy(dx: 1, dy: 1))
    }
}
