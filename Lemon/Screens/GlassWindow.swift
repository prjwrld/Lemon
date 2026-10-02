import AppKit
import SwiftUI

/// A borderless window whose SwiftUI content draws its own rounded glass shell.
/// Used by the editors, the welcome tour and the purchase screen.
final class GlassWindow: NSWindow {
    var onClose: (() -> Void)?

    init<Content: View>(size: CGSize, resizable: Bool = false, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: resizable ? [.borderless, .resizable, .fullSizeContentView] : [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        minSize = CGSize(width: min(size.width, 420), height: min(size.height, 320))
        contentView = NSHostingView(rootView: content())
        center()
    }

    // Borderless windows can't normally take typing; editors need it for text fields.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape closes the window, like a sheet.
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    func present() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

/// The rounded glass shell: title and close button at the top, content, then actions at the bottom.
struct GlassShell<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
                .help("Close")

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
            }
            content
            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Big glass panels need more body than small controls (Apple's guidance), so the window
        // colour is mixed in; this keeps text readable over busy windows behind it.
        .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.72)), in: .rect(cornerRadius: 28))
        .padding(1)
    }
}

/// Bottom row used by every editor: optional leading controls, then Cancel and the main action.
struct EditorFooter<Leading: View>: View {
    var applyTitle = "Apply"
    var canApply = true
    let onCancel: () -> Void
    let onApply: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer()
            Button("Cancel", action: onCancel).buttonStyle(.glass)
            Button(applyTitle, action: onApply)
                .buttonStyle(.glassProminent)
                .tint(.lemonDeep)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
        }
        .controlSize(.large)
    }
}

extension EditorFooter where Leading == EmptyView {
    init(applyTitle: String = "Apply", canApply: Bool = true, onCancel: @escaping () -> Void, onApply: @escaping () -> Void) {
        self.init(applyTitle: applyTitle, canApply: canApply, onCancel: onCancel, onApply: onApply) { EmptyView() }
    }
}

/// A grey-and-white checkerboard that shows where a picture is see-through.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(.white.opacity(0.9))
    }
}
