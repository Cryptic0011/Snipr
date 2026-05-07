@preconcurrency import AVFoundation
import AVKit
import SwiftUI

/// Preview pane for recorded video items, with simple in/out trim handles
/// and an Export button that runs the trimmed range through `TrimExporter`.
struct VideoTrimView: View {
    let item: CaptureItem

    @State private var player: AVPlayer
    @State private var duration: TimeInterval = 0
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var isExporting = false
    @State private var exportError: String?

    init(item: CaptureItem) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            controls
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

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.32))
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.55))
                                .frame(width: max(2, CGFloat((trimEnd - trimStart) / duration) * proxy.size.width))
                                .offset(x: CGFloat(trimStart / duration) * proxy.size.width)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 12)

                    Text(format(trimEnd))
                        .font(.caption.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }

                HStack {
                    Slider(value: $trimStart, in: 0...max(duration, 0.01), onEditingChanged: { _ in
                        trimStart = min(trimStart, max(0, trimEnd - 0.1))
                        seek(to: trimStart)
                    })
                    .frame(maxWidth: .infinity)
                    Slider(value: $trimEnd, in: 0...max(duration, 0.01), onEditingChanged: { _ in
                        trimEnd = max(trimEnd, min(duration, trimStart + 0.1))
                        seek(to: trimEnd)
                    })
                    .frame(maxWidth: .infinity)
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
            // Leave duration at 0 — UI shows "Loading video…" forever; better
            // than crashing.
        }
    }

    private func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mm = total / 60
        let ss = total % 60
        let fr = Int(((seconds - Double(total)) * 30).rounded())
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
