@preconcurrency import AVFoundation
@preconcurrency import AVKit
import SwiftUI

/// Preview pane for recorded video items, with simple in/out trim handles
/// and an Export button that runs the trimmed range through `TrimExporter`.
/// Uses AVPlayerView via NSViewRepresentable to avoid AVKit.VideoPlayer
/// metadata-initialization crashes under .accessory activation policy.
struct VideoTrimView: View {
    let item: CaptureItem

    @State private var player: AVPlayer?
    @State private var duration: TimeInterval = 0
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                AVPlayerViewWrapper(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(ProgressView())
            }

            controls
        }
        .onAppear {
            player = AVPlayer(url: item.fileURL)
        }
        .task {
            await loadDuration()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trim")
                .font(.headline)

            if duration > 0 {
                HStack(spacing: 12) {
                    Text(format(trimStart))
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .leading)

                    TrimBar(duration: duration, trimStart: $trimStart, trimEnd: $trimEnd) { time in
                        seek(to: time)
                    }

                    Text(format(trimEnd))
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }

                HStack {
                    Spacer()
                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await exportTrimmed() }
                    } label: {
                        if isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export Trim…", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isExporting || trimEnd - trimStart < 0.1)
                }
            } else {
                Text("Loading video…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: item.fileURL)
        do {
            let cmDuration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(cmDuration)
            await MainActor.run {
                duration = seconds.isFinite && seconds > 0 ? seconds : 0
                trimEnd = duration
            }
        } catch {
        }
    }

    private func seek(to seconds: TimeInterval) {
        guard let player else { return }
        // Zero tolerance so dragging a handle shows the exact frame at that
        // time, not the nearest keyframe.
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let mm = total / 60
        let ss = total % 60
        let fr = min(29, Int((seconds - Double(total)) * 30))
        return String(format: "%02d:%02d.%02d", mm, ss, fr)
    }

    @MainActor
    private func exportTrimmed() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.fileURL.deletingPathExtension().lastPathComponent + "-trimmed.mov"
        panel.allowedContentTypes = [.quickTimeMovie]
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            _ = try await TrimExporter.export(
                sourceURL: item.fileURL,
                outputURL: outURL,
                start: trimStart,
                end: trimEnd
            )
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// QuickTime-style trim control: one timeline with the kept range highlighted
/// and a draggable handle at each end. Dragging anywhere moves the nearer
/// handle and scrubs the player to it.
private struct TrimBar: View {
    let duration: TimeInterval
    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval
    var onScrub: (TimeInterval) -> Void

    private enum Handle { case start, end }
    @State private var activeHandle: Handle?

    private static let handleWidth: CGFloat = 8
    private static let minGap: TimeInterval = 0.1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let startX = x(for: trimStart, width: width)
            let endX = x(for: trimEnd, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.32))
                    .frame(height: 8)

                Rectangle()
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: max(2, endX - startX), height: 8)
                    .offset(x: startX)

                handle(at: startX, active: activeHandle == .start)
                handle(at: endX, active: activeHandle == .end)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let t = time(at: value.location.x, width: width)
                        if activeHandle == nil {
                            activeHandle = abs(t - trimStart) <= abs(t - trimEnd) ? .start : .end
                        }
                        switch activeHandle {
                        case .start:
                            trimStart = min(max(0, t), trimEnd - Self.minGap)
                            onScrub(trimStart)
                        case .end:
                            trimEnd = max(min(duration, t), trimStart + Self.minGap)
                            onScrub(trimEnd)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in activeHandle = nil }
            )
        }
        .frame(height: 24)
    }

    private func handle(at x: CGFloat, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(active ? Color.accentColor : Color.white)
            .frame(width: Self.handleWidth, height: 24)
            .shadow(radius: 1)
            .offset(x: x - Self.handleWidth / 2)
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        CGFloat(time / duration) * width
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(0, TimeInterval(x / width) * duration), duration)
    }
}

private struct AVPlayerViewWrapper: NSViewRepresentable {
    typealias NSViewType = AVPlayerView

    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
