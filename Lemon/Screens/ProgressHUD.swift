import AppKit
import SwiftUI

/// A small glass panel under the menu bar listing running and finished jobs.
final class ProgressHUD {
    private let center = JobCenter.shared
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: JobList(center: center))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }()

    func start() { watch() }

    /// Re-runs whenever a job is added or removed, or one finishes or gets a message,
    /// since those change the panel's height (Observation tracking).
    private func watch() {
        withObservationTracking {
            for job in center.jobs {
                _ = job.state
                _ = job.message
            }
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.update()
                self?.watch()
            }
        }
    }

    private func update() {
        guard !center.jobs.isEmpty else {
            panel.orderOut(nil)
            return
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 340, height: 100)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrame(NSRect(x: area.maxX - size.width - 12, y: area.maxY - size.height - 8,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }
}

private struct JobList: View {
    let center: JobCenter

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.jobs) { job in
                JobRow(job: job, onDismiss: { center.remove(job) })
            }
        }
        .padding(10)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct JobRow: View {
    let job: Job
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                switch job.state {
                case .running:
                    if let progress = job.progress {
                        ProgressView(value: progress).tint(.lemonDeep)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(.lemonDeep)
                    }
                case .finished(let urls):
                    Text(job.message ?? summary(urls)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
                case .cancelled:
                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private var icon: some View {
        switch job.state {
        case .running: ProgressView().controlSize(.small)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary).font(.title3)
        }
    }

    @ViewBuilder private var actions: some View {
        switch job.state {
        case .running:
            Button("Cancel") { job.cancel() }.buttonStyle(.glass).controlSize(.small)
        case .finished(let urls) where !urls.isEmpty:
            Button("Show") { NSWorkspace.shared.activateFileViewerSelecting(urls); onDismiss() }
                .buttonStyle(.glass).controlSize(.small)
        default:
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        }
    }

    private func summary(_ urls: [URL]) -> String {
        switch urls.count {
        case 0: "Done"
        case 1: "Saved \(urls[0].lastPathComponent)"
        default: "Saved \(urls.count) items"
        }
    }
}
