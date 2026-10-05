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
        model.isOpen = false

        panel.setFrame(frame(centeredOn: screenPoint), display: false)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.model.isOpen = true }
        return true
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
            model.isOpen = false   // the view animates this; drops are refused from now on
            model.hovered = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + WheelView.closeDuration) { [self] in
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

    init(model: WheelModel, onDrop: @escaping ([URL], Action) -> Void) {
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
        let wheel = NSHostingView(rootView: WheelView(model: model))
        wheel.frame = container.bounds
        wheel.autoresizingMask = [.width, .height]
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
