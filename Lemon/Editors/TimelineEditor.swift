import AVFoundation
import AVKit
import SwiftUI

/// Video and audio editor for Trim, Split and Bleep: preview, frame strip or waveform,
/// a draggable playhead, and the selection for each tool.
struct TimelineEditor: View {
    enum Mode { case trim, split, bleep }

    let file: URL
    let mode: Mode
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var model = TimelineModel()
    @State private var range = TimeRange(start: 0, end: 1)
    @State private var cuts: [Double] = []
    @State private var bleeps: [TimeRange] = []
    @State private var drafting: TimeRange?

    private var title: String {
        switch mode {
        case .trim: "Trim"
        case .split: "Split"
        case .bleep: "Bleep"
        }
    }

    var body: some View {
        GlassShell(title: title, subtitle: file.lastPathComponent, onClose: { model.stop(); onCancel() }) {
            ZStack {
                if model.hasVideo, let player = model.player {
                    PlayerView(player: player).clipShape(.rect(cornerRadius: 14))
                } else {
                    Image(systemName: model.loading ? "hourglass" : "waveform")
                        .font(.system(size: 64, weight: .light)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let problem = model.problem {
                    Text(problem).padding().glassEffect()
                } else if model.loading {
                    ProgressView("Preparing preview…").padding().glassEffect()
                }
            }
            .frame(minHeight: model.hasVideo ? 300 : 120)

            timeline.frame(height: 64)

            HStack(spacing: 10) {
                Button { model.seek(model.time - 1) } label: { Image(systemName: "gobackward.1") }
                Button { model.togglePlay(within: mode == .trim ? range : nil) } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill").frame(width: 18)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { model.seek(model.time + 1) } label: { Image(systemName: "goforward.1") }
                Text(timeLabel(model.time)).font(.callout.monospacedDigit())
                Spacer()
                modeControls
            }
            .buttonStyle(.glass)
        } footer: {
            EditorFooter(canApply: canApply, onCancel: { model.stop(); onCancel() }, onApply: apply)
        }
        .task {
            await model.load(file)
            range = TimeRange(start: 0, end: model.duration)
        }
        .onDisappear { model.stop() }
    }

    // MARK: Per-mode parts

    @ViewBuilder private var modeControls: some View {
        switch mode {
        case .trim:
            Text("Start \(timeLabel(range.start))  ·  End \(timeLabel(range.end))  ·  \(timeLabel(range.length))")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button("Set Start") { range.start = min(model.time, range.end - 0.1) }
            Button("Set End") { range.end = max(model.time, range.start + 0.1) }
        case .split:
            Text(cuts.isEmpty ? "Add a cut at the playhead" : "\(cuts.count + 1) parts")
                .font(.callout).foregroundStyle(.secondary)
            Button("Add Cut") {
                if model.time > 0.1, model.time < model.duration - 0.1, !cuts.contains(where: { abs($0 - model.time) < 0.1 }) {
                    cuts.append(model.time); cuts.sort()
                }
            }
            Button("Clear") { cuts.removeAll() }.disabled(cuts.isEmpty)
        case .bleep:
            Text(bleeps.isEmpty ? "Drag across the waveform to mark a bleep" : "\(bleeps.count) bleep\(bleeps.count == 1 ? "" : "s")")
                .font(.callout).foregroundStyle(.secondary)
            Button("Undo") { _ = bleeps.popLast() }.disabled(bleeps.isEmpty)
        }
    }

    private var canApply: Bool {
        guard model.duration > 0, model.problem == nil else { return false }
        switch mode {
        case .trim: return range.length > 0.05 && (range.start > 0.01 || range.end < model.duration - 0.01)
        case .split: return !cuts.isEmpty
        case .bleep: return !bleeps.isEmpty
        }
    }

    private func apply() {
        model.stop()
        switch mode {
        case .trim: onApply(.trim(range))
        case .split: onApply(.split(cuts))
        case .bleep: onApply(.bleep(bleeps))
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            let duration = max(model.duration, 0.001)
            let x: (Double) -> CGFloat = { CGFloat($0 / duration) * width }
            let t: (CGFloat) -> Double = { min(max(Double($0 / width) * duration, 0), duration) }

            ZStack(alignment: .topLeading) {
                strip(width: width, height: height)
                    .clipShape(.rect(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if mode == .bleep, abs(value.translation.width) > 3 {
                                let a = t(value.startLocation.x), b = t(value.location.x)
                                drafting = TimeRange(start: min(a, b), end: max(a, b))
                            } else {
                                model.seek(t(value.location.x))
                            }
                        }
                        .onEnded { _ in
                            if let draft = drafting, draft.length > 0.05 { bleeps.append(draft) }
                            drafting = nil
                        })

                switch mode {
                case .trim:
                    // Dim what will be cut off, and frame the kept part.
                    Rectangle().fill(.black.opacity(0.55)).frame(width: x(range.start), height: height).allowsHitTesting(false)
                    Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width - x(range.end)), height: height)
                        .offset(x: x(range.end)).allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 10).stroke(Color.lemon, lineWidth: 3)
                        .frame(width: max(8, x(range.end) - x(range.start)), height: height)
                        .offset(x: x(range.start)).allowsHitTesting(false)
                    handle(height: height).offset(x: x(range.start) - 6)
                        .gesture(DragGesture().onChanged { v in range.start = min(t(v.location.x), range.end - 0.1); model.seek(range.start) })
                    handle(height: height).offset(x: x(range.end) - 6)
                        .gesture(DragGesture().onChanged { v in range.end = max(t(v.location.x), range.start + 0.1); model.seek(range.end) })
                case .split:
                    ForEach(cuts, id: \.self) { cut in
                        Rectangle().fill(Color.lemon).frame(width: 3, height: height).offset(x: x(cut) - 1.5)
                            .onTapGesture { cuts.removeAll { $0 == cut } }
                            .help("Click to remove this cut")
                    }
                case .bleep:
                    ForEach(Array((bleeps + (drafting.map { [$0] } ?? [])).enumerated()), id: \.offset) { index, b in
                        Rectangle().fill(Color.red.opacity(0.45))
                            .frame(width: max(3, x(b.end) - x(b.start)), height: height).offset(x: x(b.start))
                            .onTapGesture { if index < bleeps.count { bleeps.remove(at: index) } }
                    }
                }

                // Playhead
                Rectangle().fill(.white).frame(width: 2, height: height + 8).offset(x: x(model.time) - 1, y: -4)
                    .shadow(radius: 2).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private func strip(width: CGFloat, height: CGFloat) -> some View {
        if !model.thumbnails.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: width / CGFloat(model.thumbnails.count), height: height).clipped()
                }
            }
        } else {
            Canvas { context, size in
                let bars = model.waveform
                guard !bars.isEmpty else { return }
                let step = size.width / CGFloat(bars.count)
                for (index, peak) in bars.enumerated() {
                    let h = max(1, CGFloat(peak) * size.height * 0.9)
                    context.fill(Path(CGRect(x: CGFloat(index) * step, y: (size.height - h) / 2, width: max(1, step - 0.5), height: h)),
                                 with: .color(.white.opacity(0.75)))
                }
            }
            .background(.black.opacity(0.25))
        }
    }

    private func handle(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.lemon)
            .frame(width: 12, height: height)
            .overlay(Capsule().fill(.black.opacity(0.4)).frame(width: 2, height: 18))
    }
}

/// Player state for the timeline editor.
@Observable
final class TimelineModel {
    var player: AVPlayer?
    var duration = 0.0
    var time = 0.0
    var playing = false
    var hasVideo = false
    var loading = true
    var problem: String?
    var thumbnails: [CGImage] = []
    var waveform: [Float] = []
    private var observer: Any?
    private var stopAt: Double?
    /// A temporary playable copy (for formats AVPlayer can't open), deleted when the editor closes.
    private var previewCopy: URL?
    private var stopped = false

    func load(_ file: URL) async {
        do {
            let info = try await FFmpeg.probe(file)
            duration = info.duration ?? 0
            hasVideo = info.hasVideo
            let playable = try await MediaPreview.playable(file)
            if playable != file { previewCopy = playable }
            // The editor may have closed while the copy was being made.
            if stopped || Task.isCancelled { removePreviewCopy(); return }
            let player = AVPlayer(url: playable)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
                MainActor.assumeIsolated { self?.tick(t.seconds) }
            }
            self.player = player
            loading = false
            if hasVideo {
                thumbnails = await MediaPreview.thumbnails(of: playable, count: 10, duration: duration)
            } else {
                waveform = await MediaPreview.waveform(of: file, bars: 300)
            }
        } catch {
            loading = false
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func tick(_ seconds: Double) {
        guard playing else { return }
        time = seconds
        if let stopAt, seconds >= stopAt { player?.pause(); playing = false }
        // Reached the end of the file: show Play again.
        if duration > 0, seconds >= duration - 0.05 { playing = false }
    }

    func seek(_ seconds: Double) {
        time = min(max(seconds, 0), duration)
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Plays from the playhead. With a range (Trim), playback stays inside it:
    /// it starts at the range's start when the playhead is outside, and stops at its end.
    func togglePlay(within range: TimeRange?) {
        guard let player else { return }
        if playing {
            player.pause()
        } else {
            stopAt = range?.end
            if let range {
                if time < range.start || time >= range.end - 0.05 { seek(range.start) }
            } else if time >= duration - 0.05 {
                seek(0)
            }
            player.play()
        }
        playing.toggle()
    }

    func stop() {
        stopped = true
        player?.pause()
        playing = false
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        removePreviewCopy()
    }

    private func removePreviewCopy() {
        if let previewCopy { try? FileManager.default.removeItem(at: previewCopy) }
        previewCopy = nil
    }
}

/// AVPlayerView without its own controls (the editor has its own).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}
