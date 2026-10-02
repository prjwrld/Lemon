import AppKit
import SwiftUI

/// Opens the right editor for a tool, and hands back what the user chose.
enum EditorPresenter {
    private static var window: GlassWindow?

    static func present(_ tool: Tool, files: [URL], completion: @escaping (ToolOptions) -> Void) {
        window?.close()
        let file = files[0]
        let isMedia = [.video, .gif, .audio].contains(FileKind(file: file))

        let finish: (ToolOptions) -> Void = { options in
            window?.close()
            completion(options)
        }
        let cancel: () -> Void = { window?.close() }

        let (size, view): (CGSize, AnyView) = switch tool {
        case .crop: (CGSize(width: 760, height: 620), AnyView(CropEditor(file: file, fileCount: files.count, onCancel: cancel, onApply: finish)))
        case .editPhoto: (CGSize(width: 900, height: 640), AnyView(PhotoEditor(file: file, onCancel: cancel, onApply: finish)))
        case .annotate: (CGSize(width: 820, height: 640), AnyView(AnnotateEditor(file: file, onCancel: cancel, onApply: finish)))
        case .background: (CGSize(width: 760, height: 620), AnyView(BackgroundEditor(file: file, onCancel: cancel, onApply: finish)))
        case .redact: (CGSize(width: 780, height: 620), AnyView(RedactEditor(file: file, onCancel: cancel, onApply: finish)))
        case .collage: (CGSize(width: 820, height: 640), AnyView(CollageEditor(files: files, onCancel: cancel, onApply: finish)))
        case .trim: (CGSize(width: 800, height: isMedia && FileKind(file: file) == .audio ? 380 : 640),
                     AnyView(TimelineEditor(file: file, mode: .trim, onCancel: cancel, onApply: finish)))
        case .split: (CGSize(width: 800, height: FileKind(file: file) == .audio ? 380 : 640),
                      AnyView(TimelineEditor(file: file, mode: .split, onCancel: cancel, onApply: finish)))
        case .bleep: (CGSize(width: 800, height: FileKind(file: file) == .audio ? 380 : 640),
                      AnyView(TimelineEditor(file: file, mode: .bleep, onCancel: cancel, onApply: finish)))
        case .speed: (CGSize(width: 520, height: 340), AnyView(SpeedEditor(file: file, onCancel: cancel, onApply: finish)))
        case .snapshots: (CGSize(width: 680, height: 380), AnyView(SnapshotsEditor(file: file, onCancel: cancel, onApply: finish)))
        case .organize: (CGSize(width: 820, height: 640), AnyView(PagesEditor(file: file, onCancel: cancel, onApply: finish)))
        case .metadata: (CGSize(width: 820, height: 560), AnyView(MetadataEditor(file: file, onCancel: cancel, onApply: finish)))
        default:
            (CGSize.zero, AnyView(EmptyView()))
        }
        guard size != .zero else { completion(.none); return }

        let window = GlassWindow(size: size, resizable: true) { view }
        window.onClose = { EditorPresenter.window = nil }
        self.window = window
        window.present()
    }
}
