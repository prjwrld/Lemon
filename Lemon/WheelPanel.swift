import AppKit
import SwiftUI

/// Shows and hides the floating wheel, and reports which format was chosen.
final class WheelController {
    var onChoose: ((_ files: [URL], _ format: ImageFormat) -> Void)?

    private let model = WheelModel()
    private lazy var panel = WheelPanel(model: model) { [weak self] files, format in
        self?.onChoose?(files, format)
        self?.hide()
    }

    /// Returns false (and shows nothing) if Lemon has no choices for these files.
    func show(files: [URL], at screenPoint: NSPoint) -> Bool {
        let choices = ImageFormat.choices(for: files)
        guard !choices.isEmpty else { return false }

        model.files = files
        model.choices = choices
        model.hovered = nil
        model.isOpen = false

        panel.setFrame(frame(centeredOn: screenPoint), display: false)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.model.isOpen = true }
        return true
    }

    func hide() {
        // A short pause lets a drop that's still arriving finish first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            model.isOpen = false
            model.hovered = nil
            panel.orderOut(nil)
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
    static let size: CGFloat = 290 // a little bigger than the wheel, for its edge glow

    init(model: WheelModel, onDrop: @escaping ([URL], ImageFormat) -> Void) {
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
    private let onDrop: ([URL], ImageFormat) -> Void

    init(model: WheelModel, onDrop: @escaping ([URL], ImageFormat) -> Void) {
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
        guard let choice = model.hoveredChoice else { return false }
        let files = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !files.isEmpty else { return false }
        onDrop(files, choice)
        return true
    }

    private func track(_ sender: any NSDraggingInfo) -> NSDragOperation {
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
