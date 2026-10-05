import AppKit
import SwiftUI

/// Shows and hides the floating wheel, and reports which choice was dropped on.
final class WheelController {
    var onChoose: ((_ files: [URL], _ action: Action) -> Void)?

    private let model = WheelModel()
    /// Counts wheels shown, so a late hide() can tell it belongs to an older one.
    private var generation = 0
    private lazy var panel = WheelPanel(model: model) { [weak self] files, action in
        self?.onChoose?(files, action)
        self?.hide()
    }

    /// Returns false (and shows nothing) if Lemon has no choices for these files.
    func show(files: [URL], at screenPoint: NSPoint, mode: WheelMode) -> Bool {
        let choices = ActionCatalog.actions(for: files, mode: mode)
        guard !choices.isEmpty else { return false }

        generation += 1
        model.files = files
        model.mode = mode
        model.choices = choices
        model.hovered = nil
        model.isOpen = true

        panel.setFrame(frame(centeredOn: screenPoint), display: true)
        if !panel.isVisible { panel.collapse() }   // never flash at full size
        panel.orderFrontRegardless()
        panel.animateOpen()
        return true
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

/// A see-through window that floats above everything and never steals focus.
final class WheelPanel: NSPanel {
    static let size: CGFloat = 330 // bigger than the wheel, to fit its shadow

    /// The SwiftUI wheel. Opening and closing move its layer with Core Animation, which runs
    /// in the system's renderer at the display's full frame rate, not in Lemon's own drawing.
    private let wheel: NSHostingView<WheelView>

    init(model: WheelModel, onDrop: @escaping ([URL], Action) -> Void) {
        wheel = NSHostingView(rootView: WheelView(model: model))
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
        // The drop target sits on top of the wheel, so it receives every drag.
        let dropTarget = DropTargetView(model: model, onDrop: onDrop)
        dropTarget.frame = container.bounds
        dropTarget.autoresizingMask = [.width, .height]
        container.addSubview(wheel)
        container.addSubview(dropTarget)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
final class DropTargetView: NSView {
    private let model: WheelModel
    private let onDrop: ([URL], Action) -> Void

    init(model: WheelModel, onDrop: @escaping ([URL], Action) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
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
        let location = convert(sender.draggingLocation, from: nil)
        let fromCenter = CGPoint(x: location.x - bounds.midX, y: location.y - bounds.midY)
        let slice = model.geometry.slice(at: fromCenter)
        if slice != model.hovered {
            model.hovered = slice
            if slice != nil { Feedback.hover() }
        }
        // .copy tells Finder we're making a copy, so the original is left alone.
        return slice == nil ? [] : .copy
    }
}
