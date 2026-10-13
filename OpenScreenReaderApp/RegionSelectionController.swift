import AppKit
import CoreGraphics

struct ScreenRegionSelection: Equatable, Sendable {
    let displayID: UInt32
    let rectInScreenPoints: CGRect
    let rectInBackingPixels: CGRect
    let backingScaleFactor: CGFloat
    var displayGeometry: DisplaySelectionGeometry? = nil
    var topologyRevision: UInt64? = nil
    /// Set for a click: the normalized point whose paragraph should be read.
    var focus: CGPoint? = nil

    /// A click reads only the paragraph under the pointer; the rest of the area is discarded.
    func focusedText(_ result: OCRResult) -> OCRResult {
        guard let focus else { return result }
        return result.block(around: focus, in: rectInScreenPoints.size) ?? OCRResult(lines: [])
    }

    /// Where the control's opening flight starts: the dragged frame, or the clicked spot.
    var flightOrigin: CGRect {
        guard let focus else { return rectInScreenPoints }
        let point = CGPoint(x: rectInScreenPoints.minX + focus.x * rectInScreenPoints.width,
                            y: rectInScreenPoints.minY + focus.y * rectInScreenPoints.height)
        return CGRect(x: point.x - 20, y: point.y - 12, width: 40, height: 24)
    }
}

@MainActor
final class DisplayTopology: NSObject {
    static let shared = DisplayTopology()
    private(set) var revision: UInt64 = 0

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenTopologyDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screenTopologyDidChange() { revision += 1 }
}

struct DisplaySelectionGeometry: Equatable, Sendable {
    let displayID: UInt32
    let frameInScreenPoints: CGRect
    let backingScaleFactor: CGFloat

    var localBounds: CGRect {
        CGRect(origin: .zero, size: frameInScreenPoints.size)
    }

    func selection(from start: CGPoint, to end: CGPoint) -> ScreenRegionSelection? {
        selection(in: CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ))
    }

    /// A bounded area around a click, kept inside the display. Only this area is
    /// captured, and only the clicked paragraph within it is read.
    static let clickArea = CGSize(width: 1200, height: 800)
    func clickSelection(at point: CGPoint) -> ScreenRegionSelection? {
        let width = min(Self.clickArea.width, localBounds.width)
        let height = min(Self.clickArea.height, localBounds.height)
        let x = min(max(point.x - width / 2, 0), localBounds.width - width)
        let y = min(max(point.y - height / 2, 0), localBounds.height - height)
        guard var selection = selection(in: CGRect(x: x, y: y, width: width, height: height)) else { return nil }
        selection.focus = CGPoint(x: (point.x - x) / width, y: (point.y - y) / height)
        return selection
    }

    func selection(in rect: CGRect) -> ScreenRegionSelection? {
        let localRect = rect.standardized.intersection(localBounds)

        guard !localRect.isNull, localRect.width >= 3, localRect.height >= 3 else {
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

/// The drag in progress, with the modifiers people know from ⌘⇧4:
/// Space moves the selection, Shift locks the edge that did not move first,
/// Option grows it around the starting point.
struct SelectionGesture: Equatable {
    private enum Axis { case horizontal, vertical }
    private(set) var anchor: CGPoint
    private(set) var pointer: CGPoint
    private var fromCenter = false
    private var moving = false
    private var shiftLocked: CGPoint?
    private var axis: Axis?

    init(start: CGPoint) {
        anchor = start
        pointer = start
    }

    mutating func move(to point: CGPoint) {
        let delta = CGPoint(x: point.x - pointer.x, y: point.y - pointer.y)
        pointer = point
        if moving {
            anchor.x += delta.x; anchor.y += delta.y
            shiftLocked?.x += delta.x; shiftLocked?.y += delta.y
            return
        }
        if let locked = shiftLocked, axis == nil {
            let dx = point.x - locked.x, dy = point.y - locked.y
            if max(abs(dx), abs(dy)) >= 2 { axis = abs(dx) >= abs(dy) ? .horizontal : .vertical }
        }
    }

    mutating func setModifiers(option: Bool, shift: Bool) {
        fromCenter = option
        if shift, shiftLocked == nil { shiftLocked = pointer; axis = nil }
        if !shift { shiftLocked = nil; axis = nil }
    }

    mutating func setMoving(_ value: Bool) { moving = value }

    private var effectivePointer: CGPoint {
        guard let locked = shiftLocked, let axis else { return shiftLocked ?? pointer }
        return axis == .horizontal ? CGPoint(x: pointer.x, y: locked.y) : CGPoint(x: locked.x, y: pointer.y)
    }

    var rect: CGRect {
        let end = effectivePointer
        let dx = end.x - anchor.x, dy = end.y - anchor.y
        if fromCenter {
            return CGRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y), width: abs(dx), height: abs(dy))
    }
}

/// A short instruction for the first few selections; after that the overlay stays silent.
enum SelectionHint {
    static let limit = 5
    static let key = "selectionHintCount.v1"

    /// Returns true when the hint should show this time and counts it.
    static func consume(_ defaults: UserDefaults) -> Bool {
        let count = defaults.integer(forKey: key)
        guard count < limit else { return false }
        defaults.set(count + 1, forKey: key)
        return true
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
    private var topologyRevision: UInt64 = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = InterfaceSoundPlayer.defaults) {
        self.defaults = defaults
        super.init()
    }

    isolated deinit { cancel() }

    func start(
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        cancel()
        self.onSelection = onSelection
        self.onCancel = onCancel
        topologyRevision = DisplayTopology.shared.revision

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let pointer = NSEvent.mouseLocation
        let hintScreen = SelectionHint.consume(defaults)
            ? NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.screens.first : nil
        panels = NSScreen.screens.compactMap { screen in
            SelectionOverlayPanel(
                screen: screen,
                showsHint: screen === hintScreen,
                onSelection: { [weak self] selection in
                    self?.finish(with: selection)
                },
                onCancel: { [weak self] in
                    self?.finishAsCancelled()
                }
            )
        }

        // Take keyboard input through the panel without activating Saywing:
        // activation also raises its Settings/dictation windows over the source app.
        // The dimming eases in instead of jumping in brightness; input is live at once.
        panels.forEach { $0.alphaValue = 0; $0.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panels.forEach { $0.animator().alphaValue = 1 }
        }
        (panels.first { $0.frame.contains(pointer) } ?? panels.first)?.makeKey()
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
        guard topologyRevision == DisplayTopology.shared.revision else {
            finishAsCancelled()
            return
        }
        var selection = selection
        selection.topologyRevision = topologyRevision
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
    override var canBecomeMain: Bool { false }

    init(
        screen: NSScreen,
        showsHint: Bool,
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
        title = String(localized: "Select Screen Region")
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none

        let selectionView = SelectionOverlayView(
            screen: screen,
            showsHint: showsHint,
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
    private var gesture: SelectionGesture?
    private var selectionRect: CGRect { gesture.map { $0.rect.intersection(bounds) } ?? .zero }
    private var hint: NSView?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(
        screen: NSScreen,
        showsHint: Bool,
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
        setAccessibilityHelp(String(localized: "Drag over the text to read, or click a paragraph. Hold Space to move the selection, Shift to lock an edge, Option to grow it from the centre. Press Escape to cancel."))
        if showsHint { addHint(screen: screen) }
    }

    /// A small pill under the menu bar for the first few selections.
    private func addHint(screen: NSScreen) {
        let label = NSTextField(labelWithString: String(localized: "Drag over text or click a paragraph  ·  Space moves  ·  Esc cancels"))
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .white
        var size = label.intrinsicContentSize
        size.width = ceil(size.width) + 4
        let pill = NSView(frame: CGRect(x: 0, y: 0, width: size.width + 28, height: size.height + 14))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(srgbRed: 12 / 255, green: 31 / 255, blue: 26 / 255, alpha: 0.88).cgColor
        pill.layer?.cornerRadius = pill.frame.height / 2
        pill.layer?.borderWidth = 0.75
        pill.layer?.borderColor = NSColor(srgbRed: 168 / 255, green: 213 / 255, blue: 189 / 255, alpha: 0.35).cgColor
        label.frame = CGRect(x: 14, y: 7, width: size.width, height: size.height)
        pill.addSubview(label)
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        pill.setFrameOrigin(CGPoint(x: (screen.frame.width - pill.frame.width) / 2,
                                    y: screen.frame.height - menuBar - pill.frame.height - 24))
        pill.setAccessibilityElement(false)
        addSubview(pill)
        hint = pill
    }

    private func dismissHint() {
        guard let hint else { return }
        self.hint = nil
        // The overlay closes after the selection, which removes the faded pill with it.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            hint.animator().alphaValue = 0
        }
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
        dismissHint()
        var gesture = SelectionGesture(start: convert(event.locationInWindow, from: nil))
        gesture.setModifiers(option: event.modifierFlags.contains(.option), shift: false)
        self.gesture = gesture
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard gesture != nil else { return }
        gesture?.setModifiers(option: event.modifierFlags.contains(.option), shift: event.modifierFlags.contains(.shift))
        gesture?.move(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        guard gesture != nil else { return super.flagsChanged(with: event) }
        gesture?.setModifiers(option: event.modifierFlags.contains(.option), shift: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        gesture?.move(to: point)
        guard geometry.displayID != 0, let gesture else { onCancel(); return }
        // A click without a drag reads the paragraph under the pointer.
        let isClick = gesture.rect.width < 3 && gesture.rect.height < 3
        guard let selection = isClick ? geometry.clickSelection(at: point) : geometry.selection(in: gesture.rect) else {
            onCancel()
            return
        }

        onSelection(selection)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel()
        case 49: if !event.isARepeat { gesture?.setMoving(true) }
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { gesture?.setMoving(false) } else { super.keyUp(with: event) }
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
            calibratedRed: 0xA8 / 255,
            green: 0xD5 / 255,
            blue: 0xBD / 255,
            alpha: 1
        ).cgColor)
        context.setLineWidth(2)
        context.stroke(selectionRect.insetBy(dx: 1, dy: 1))
    }
}
