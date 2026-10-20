import AppKit
import SwiftUI

/// Shows and hides the floating wheel, and reports which choice was dropped on (or clicked).
final class WheelController {
    /// How the wheel is used: files dropped on a slice while dragging (the Shift-drag shortcut), or a slice
    /// clicked (Finder's right-click menu, where the files are already chosen and nothing is being dragged).
    enum Interaction { case drag, click }

    var onChoose: ((_ files: [URL], _ action: Action) -> Void)?

    private let model = WheelModel()
    /// Counts wheels shown, so a late hide() can tell it belongs to an older one.
    private var generation = 0
    private lazy var panel: WheelPanel = {
        let panel = WheelPanel(model: model) { [weak self] files, action in
            self?.onChoose?(files, action)
            self?.hide()
        }
        panel.onDismiss = { [weak self] in self?.hide(after: 0) }
        panel.onResignKey = { [weak self] in self?.lostKeyStatus() }
        return panel
    }()

    // Click mode: the wheel takes the keyboard (for Esc) and closes on a click anywhere else.
    private var interaction = Interaction.drag
    private var clickMonitors: [Any] = []
    private var openedAt: TimeInterval = 0
    private var forgaveKeyLoss = false

    /// Returns false (and shows nothing) if Lemon has no choices for these files.
    func show(files: [URL], at screenPoint: NSPoint, mode: WheelMode, interaction: Interaction = .drag) -> Bool {
        let choices = ActionCatalog.actions(for: files, mode: mode)
        guard !choices.isEmpty else { return false }

        generation += 1
        model.files = files
        model.mode = mode
        model.choices = choices
        model.hovered = nil
        model.isOpen = true

        endClickMode()
        self.interaction = interaction
        panel.interaction = interaction
        panel.setFrame(frame(centeredOn: screenPoint), display: true)
        if !panel.isVisible { panel.collapse() }   // never flash at full size
        panel.orderFrontRegardless()
        if interaction == .click { beginClickMode() }
        panel.animateOpen()
        return true
    }

    /// Makes the wheel key (it's a non-activating panel, so the app in front stays in front) and watches
    /// for clicks outside it. Mouse-down monitors need no special permission.
    private func beginClickMode() {
        openedAt = ProcessInfo.processInfo.systemUptime
        forgaveKeyLoss = false
        panel.makeKey()
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: buttons) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(after: 0) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: buttons) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.hide(after: 0) }
            }
            return event
        }
        clickMonitors = [global, local].compactMap { $0 }
    }

    private func endClickMode() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    /// Another window took the keyboard: close. Except once just after opening, when the app whose menu
    /// opened the wheel (Finder) may take it back as its menu closes; then the wheel takes it again.
    private func lostKeyStatus() {
        guard interaction == .click, model.isOpen else { return }
        if !forgaveKeyLoss, ProcessInfo.processInfo.systemUptime - openedAt < 1 {
            forgaveKeyLoss = true
            let current = generation
            DispatchQueue.main.async { [self] in
                if generation == current, model.isOpen { panel.makeKey() }
            }
            return
        }
        hide(after: 0)
    }

    /// Sets the wheel's window up once, invisibly, at launch. Its first-ever display does
    /// layout work that would otherwise disturb the first opening animation.
    func prepare() {
        model.choices = ActionCatalog.outputs(for: .image).map(Action.convert)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.collapse()
    }

    /// Switches between the formats and tools wheels while it's open.
    func switchMode(to mode: WheelMode) -> Bool {
        let choices = ActionCatalog.actions(for: model.files, mode: mode)
        guard !choices.isEmpty else { return false }
        model.mode = mode
        model.choices = choices
        model.hovered = nil
        return true
    }

    #if DEBUG
    /// Design helper: highlight a slice without dragging.
    func demoHover(_ index: Int?) { model.hovered = index }
    #endif

    /// Closes the wheel with its closing animation, then removes the window.
    /// - Parameter delay: after the mouse is released, a short pause lets a drop that's still
    ///   arriving finish first. Letting go of the keys closes at once (delay 0).
    /// If a new wheel opens meanwhile (a quick second drag, or the keys held again), it's left alone.
    func hide(after delay: TimeInterval = 0.25) {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard generation == current, model.isOpen else { return }
            model.isOpen = false   // drops are refused from now on
            endClickMode()
            model.hovered = nil
            panel.animateClose { [self] in
                guard generation == current else { return }
                panel.orderOut(nil)
            }
        }
    }

    /// Centres the wheel on the pointer, but keeps it fully on screen.
    private func frame(centeredOn point: NSPoint) -> NSRect {
        let size = WheelPanel.size
        var frame = NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size)
            frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size)
        }
        return frame
    }
}

/// A see-through window that floats above everything and never steals focus. In click mode it takes
/// the keyboard (for Esc) without making Lemon the active app.
final class WheelPanel: NSPanel {
    static let size: CGFloat = 330 // bigger than the wheel, to fit its shadow

    /// The SwiftUI wheel. Opening and closing move its layer with Core Animation, which runs
    /// in the system's renderer at the display's full frame rate, not in Lemon's own drawing.
    private let wheel: NSHostingView<WheelView>
    private let dropTarget: DropTargetView

    var interaction = WheelController.Interaction.drag {
        didSet {
            dropTarget.interaction = interaction
            acceptsMouseMovedEvents = interaction == .click
        }
    }
    /// Esc, or a click on the wheel outside its slices.
    var onDismiss: (() -> Void)? {
        didSet { dropTarget.onDismiss = onDismiss }
    }
    var onResignKey: (() -> Void)?

    init(model: WheelModel, onDrop: @escaping ([URL], Action) -> Void) {
        wheel = NSHostingView(rootView: WheelView(model: model))
        // The drop target sits on top of the wheel, so it receives every drag (and click).
        dropTarget = DropTargetView(model: model, onDrop: onDrop)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wheel.frame = container.bounds
        wheel.autoresizingMask = [.width, .height]
        wheel.wantsLayer = true
        dropTarget.frame = container.bounds
        dropTarget.autoresizingMask = [.width, .height]
        container.addSubview(wheel)
        container.addSubview(dropTarget)
        contentView = container
    }

    override var canBecomeKey: Bool { interaction == .click }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }   // Esc
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    // MARK: Opening and closing
    //
    // Pure motion, no fading: the wheel grows out of the pointer,
    // settling with a soft spring; closing shrinks it smoothly back into the pointer.
    // Both are interruptible: holding the keys again mid-close reverses from where it is.
    // With Reduce Motion it simply appears and disappears.
    //
    // The scaling happens around the wheel's centre (the pointer). AppKit owns the layer's
    // anchor point and resets it during layout, so instead of moving the anchor, the centre
    // is built into the transform itself: move the centre to the anchor, scale, move it back.

    /// Closed size: a point under the pointer (exactly 0 can't be reversed by Core Animation).
    private static let closedScale: CGFloat = 0.001

    /// Puts the wheel in its closed state (a point under the pointer) without animating.
    func collapse() {
        guard let layer = wheel.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.transform = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? CATransform3DIdentity : Self.scale(Self.closedScale, aroundCentreOf: layer)
        CATransaction.commit()
    }

    func animateOpen() {
        guard let layer = wheel.layer else { return }
        // Start from wherever the wheel is now (closed, or part-way through closing), so it never jumps.
        let from = (layer.presentation() ?? layer).transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.transform = CATransform3DIdentity
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.add(Self.spring(from: from, to: CATransform3DIdentity, response: 0.36, damping: 0.78), forKey: "open")
        }
        CATransaction.commit()
    }

    func animateClose(completion: @escaping () -> Void) {
        guard let layer = wheel.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            completion()
            return
        }
        let from = (layer.presentation() ?? layer).transform
        let closed = Self.scale(Self.closedScale, aroundCentreOf: layer)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        layer.removeAllAnimations()
        layer.transform = closed
        // No bounce when closing: it glides into the pointer and eases out to nothing.
        layer.add(Self.spring(from: from, to: closed, response: 0.3, damping: 1), forKey: "close")
        CATransaction.commit()
    }

    /// A transform that scales the layer around its centre, wherever AppKit put its anchor point.
    private static func scale(_ factor: CGFloat, aroundCentreOf layer: CALayer) -> CATransform3D {
        let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(dx, dy, 0)
        transform = CATransform3DScale(transform, factor, factor, 1)
        return CATransform3DTranslate(transform, -dx, -dy, 0)
    }

    /// A spring like SwiftUI's `.spring(response:dampingFraction:)`. Between two pure
    /// scale-around-a-point transforms, Core Animation's in-between steps stay centred.
    private static func spring(from: CATransform3D, to: CATransform3D,
                               response: CGFloat, damping: CGFloat) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: to)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * damping / response
        animation.duration = min(animation.settlingDuration, 0.6)
        return animation
    }
}

/// An invisible view that accepts dropped files and tracks which slice is under the pointer.
/// In click mode it follows the pointer instead, and a click chooses the slice under it.
final class DropTargetView: NSView {
    private let model: WheelModel
    private let onDrop: ([URL], Action) -> Void
    var interaction = WheelController.Interaction.drag
    var onDismiss: (() -> Void)?

    init(model: WheelModel, onDrop: @escaping ([URL], Action) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Top-left origin with y pointing down, the same as SwiftUI.
    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        model.hovered = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard model.isOpen, let choice = model.hoveredChoice else { return false }
        let files = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !files.isEmpty else { return false }
        onDrop(files, choice)
        return true
    }

    private func track(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // While the wheel is closing it no longer takes drops.
        guard model.isOpen else {
            model.hovered = nil
            return []
        }
        let slice = hover(at: sender.draggingLocation)
        // .copy tells Finder we're making a copy, so the original is left alone.
        return slice == nil ? [] : .copy
    }

    /// Highlights the slice under a point in window coordinates, and returns it.
    @discardableResult
    private func hover(at windowPoint: NSPoint) -> Int? {
        let slice = model.geometry.slice(at: fromCenter(windowPoint))
        if slice != model.hovered {
            model.hovered = slice
            if slice != nil { Feedback.hover() }
        }
        return slice
    }

    private func fromCenter(_ windowPoint: NSPoint) -> CGPoint {
        let location = convert(windowPoint, from: nil)
        return CGPoint(x: location.x - bounds.midX, y: location.y - bounds.midY)
    }

    // MARK: Click mode

    /// The wheel opens under the pointer of an app that's in front, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var clicking: Bool { interaction == .click && model.isOpen }

    override func mouseEntered(with event: NSEvent) {
        if clicking { hover(at: event.locationInWindow) }
    }

    override func mouseMoved(with event: NSEvent) {
        if clicking { hover(at: event.locationInWindow) }
    }

    override func mouseDragged(with event: NSEvent) {
        if clicking { hover(at: event.locationInWindow) }
    }

    override func mouseExited(with event: NSEvent) {
        if clicking { model.hovered = nil }
    }

    override func mouseDown(with event: NSEvent) {
        if clicking { hover(at: event.locationInWindow) }
    }

    /// Choosing happens on release, so pressing, sliding to another slice and letting go also works.
    /// A click on the wheel's see-through surroundings closes it; one in the middle does nothing.
    override func mouseUp(with event: NSEvent) {
        guard clicking else { return }
        if hover(at: event.locationInWindow) != nil, let choice = model.hoveredChoice {
            onDrop(model.files, choice)
        } else {
            let point = fromCenter(event.locationInWindow)
            if hypot(point.x, point.y) > model.geometry.diameter / 2 { onDismiss?() }
        }
    }
}
