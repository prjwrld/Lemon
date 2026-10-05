import PDFKit
import SwiftUI

/// Choose a new playback speed.
struct SpeedEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void
    @State private var factor = 2.0
    private let choices = [0.25, 0.5, 0.75, 1.25, 1.5, 2, 3, 4]

    var body: some View {
        GlassShell(title: "Speed", subtitle: file.lastPathComponent, onClose: onCancel) {
            VStack(spacing: 18) {
                Text(label(factor)).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                Picker("Speed", selection: $factor) {
                    ForEach(choices, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(factor > 1 ? "Faster and shorter. Sound keeps its pitch." : "Slower and longer. Sound keeps its pitch.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        } footer: {
            EditorFooter(onCancel: onCancel, onApply: { onApply(.speed(factor)) })
        }
    }

    private func label(_ value: Double) -> String {
        (value == value.rounded() ? String(Int(value)) : String(value)) + "×"
    }
}

/// Choose how many evenly spaced pictures to take from a video.
struct SnapshotsEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void
    @State private var count = 6
    @State private var strip: [CGImage] = []
    @State private var duration = 0.0

    var body: some View {
        GlassShell(title: "Snapshots", subtitle: file.lastPathComponent, onClose: onCancel) {
            VStack(spacing: 14) {
                if strip.isEmpty {
                    ProgressView().frame(height: 150)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(strip.enumerated()), id: \.offset) { _, image in
                                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 120)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }
                Stepper("Take \(count) pictures, evenly spaced", value: $count, in: 2...60)
                Text("Saved as JPG files in a “Snapshots” folder.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        } footer: {
            EditorFooter(applyTitle: "Save \(count) Snapshots", onCancel: onCancel, onApply: { onApply(.snapshots(count)) })
        }
        .task(id: count) {
            if duration == 0 { duration = (try? await FFmpeg.probe(file))?.duration ?? 0 }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, duration > 0 else { return }
            strip = await MediaPreview.thumbnails(of: file, count: min(count, 12), duration: duration)
        }
    }
}

/// Reorder, turn, copy and remove PDF pages.
struct PagesEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var pages: [PageEdit] = []
    @State private var thumbnails: [Int: CGImage] = [:]
    @State private var selection: UUID?

    var body: some View {
        GlassShell(title: "Pages", subtitle: "\(file.lastPathComponent) — drag pages to reorder", onClose: onCancel) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { position, page in
                        VStack(spacing: 6) {
                            Group {
                                if let image = thumbnails[page.sourceIndex] {
                                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                                } else {
                                    Rectangle().fill(.white.opacity(0.2))
                                }
                            }
                            .frame(height: 150)
                            .rotationEffect(.degrees(Double(page.rotation)))
                            .shadow(radius: 3)
                            Text("\(position + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(selection == page.id ? Color.lemon.opacity(0.35) : .clear, in: .rect(cornerRadius: 12))
                        .onTapGesture { selection = page.id }
                        .draggable(page.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                                  let from = pages.firstIndex(where: { $0.id == id }) else { return false }
                            let moved = pages.remove(at: from)
                            pages.insert(moved, at: min(position, pages.count))
                            return true
                        }
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 380)
        } footer: {
            EditorFooter(canApply: !pages.isEmpty, onCancel: onCancel, onApply: { onApply(.pages(pages)) }) {
                Group {
                    Button { change { $0.rotation -= 90 } } label: { Image(systemName: "rotate.left") }.help("Turn left")
                    Button { change { $0.rotation += 90 } } label: { Image(systemName: "rotate.right") }.help("Turn right")
                    Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate")
                    Button { pages.removeAll { $0.id == selection }; selection = nil } label: { Image(systemName: "trash") }
                        .help("Remove")
                }
                .buttonStyle(.glass)
                .disabled(selection == nil)
            }
        }
        .task {
            guard let document = try? PDFTools.open(file) else { return }
            pages = (0..<document.pageCount).map { PageEdit(sourceIndex: $0) }
            for await page in MediaPreview.pageThumbnails(of: file) {
                thumbnails[page.index] = page.image
            }
        }
    }

    private func change(_ edit: (inout PageEdit) -> Void) {
        guard let index = pages.firstIndex(where: { $0.id == selection }) else { return }
        edit(&pages[index])
    }

    private func duplicate() {
        guard let index = pages.firstIndex(where: { $0.id == selection }) else { return }
        var copy = pages[index]
        copy.id = UUID()
        pages.insert(copy, at: index + 1)
    }
}

/// Look at, change or remove a file's hidden details.
struct MetadataEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var rows: [(String, String)] = []
    @State private var edit = MetadataEdit()
    @State private var title = ""
    @State private var author = ""
    @State private var copyright = ""
    @State private var comment = ""

    var body: some View {
        GlassShell(title: "Metadata", subtitle: file.lastPathComponent, onClose: onCancel) {
            HStack(alignment: .top, spacing: 16) {
                List(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text(row.0).font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(row.1).font(.caption).textSelection(.enabled)
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay { if rows.isEmpty { Text("No details found").foregroundStyle(.secondary) } }

                Form {
                    Section("Change") {
                        TextField("Title", text: $title)
                        TextField("Author", text: $author)
                        TextField("Copyright", text: $copyright)
                        TextField("Comment", text: $comment)
                    }
                    Section("Remove") {
                        Toggle("Remove location", isOn: $edit.removeLocation)
                        Toggle("Remove all details", isOn: $edit.removeAll)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: 280)
            }
        } footer: {
            EditorFooter(applyTitle: "Save Copy", canApply: hasChanges, onCancel: onCancel, onApply: apply)
        }
        .task {
            rows = switch FileKind(file: file) {
            case .image, .svg: ImageTools.describeMetadata(file)
            case .pdf: PDFTools.describeMetadata(file)
            default: await MediaTools.describeMetadata(file)
            }
        }
    }

    private var hasChanges: Bool {
        edit.removeAll || edit.removeLocation || ![title, author, copyright, comment].allSatisfy(\.isEmpty)
    }

    private func apply() {
        var result = edit
        if !title.isEmpty { result.title = title }
        if !author.isEmpty { result.author = author }
        if !copyright.isEmpty { result.copyright = copyright }
        if !comment.isEmpty { result.comment = comment }
        onApply(.metadata(result))
    }
}
