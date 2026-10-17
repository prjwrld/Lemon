import AppKit
import SwiftUI

/// A borderless window whose SwiftUI content draws its own rounded glass shell.
/// Used by the editors, the welcome tour and the purchase screen.
final class GlassWindow: NSWindow {
    var onClose: (() -> Void)?

    /// Clear room around the glass for its shadow. The shadow is drawn by SwiftUI so it follows the
    /// rounded shape; macOS's own shadow for a borderless window is a rectangle with a hairline edge.
    static let shadowMargin: CGFloat = 28

    /// `size` is the size of the glass itself; the window is a little bigger to fit the shadow.
    init<Content: View>(size: CGSize, resizable: Bool = false, @ViewBuilder content: () -> Content) {
        let margin = Self.shadowMargin
        super.init(
            contentRect: NSRect(origin: .zero, size: CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin)),
            styleMask: resizable ? [.borderless, .resizable, .fullSizeContentView] : [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        minSize = CGSize(width: min(size.width, 420) + 2 * margin, height: min(size.height, 320) + 2 * margin)
        contentView = NSHostingView(rootView: content().padding(margin))
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

/// The rounded window shell: title and close button at the top, content, then actions at the bottom.
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
        // Drag anywhere that isn't a control (buttons, fields and editor handles keep their own drags).
        .contentShape(.rect(cornerRadius: 26))
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        // A solid window, like a normal Mac window: no see-through blur of whatever is behind it.
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
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

extension View {
    /// A quiet raised card inside a window: a faint fill and a hairline edge (no see-through blur).
    func card(cornerRadius: CGFloat = 16) -> some View {
        background(Color.primary.opacity(0.05), in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.08)))
    }
}
