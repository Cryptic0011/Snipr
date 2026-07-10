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
    @State private var backdrop: VideoBackdrop?
    @State private var style = ExportStyle.load()
    @State private var showStylePopover = false
    @State private var customImageName: String?

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                AVPlayerViewWrapper(player: player)
                    // Constrain to the video's own aspect so the backdrop —
                    // not AVPlayerView's black letterboxing — fills the pane.
                    .aspectRatio(videoAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: backdrop == nil ? 0 : style.cornerRadius))
                    .padding(backdrop == nil ? 0 : previewPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { backdropPreview }
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
            backdrop = VideoBackdrop.loadSelection()
            if case .customImage(let url) = backdrop {
                customImageName = url.lastPathComponent
            }
        }
        .task {
            await loadDuration()
        }
        .onChange(of: style) { _, newValue in newValue.save() }
        .onChange(of: backdrop) { _, newValue in VideoBackdrop.saveSelection(newValue) }
    }

    private var videoAspect: CGFloat {
        CGFloat(max(1, item.pixelWidth)) / CGFloat(max(1, item.pixelHeight))
    }

    /// Preview-scale approximation of the export padding.
    private var previewPadding: CGFloat {
        24 * style.paddingFraction / 0.08
    }

    @ViewBuilder
    private var backdropPreview: some View {
        switch backdrop {
        case .gradient(let style):
            style.previewGradient
        case .bundled, .wallpaper, .customImage:
            if let image = backdrop?.resolveImage(for: nil) {
                Image(nsImage: image).resizable().scaledToFill().clipped()
            } else {
                Color.black
            }
        case .color(let rgba):
            Color(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        case nil:
            Color.black
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                if case .color(let rgba) = backdrop { return rgba.color }
                return Color.black
            },
            set: { backdrop = .color(RGBA(color: $0)) }
        )
    }

    private var stylePopover: some View {
        Form {
            Section("Background") {
                Picker("Preset", selection: $backdrop) {
                    Text("None").tag(VideoBackdrop?.none)
                    ForEach(VideoBackdrop.pickerGroups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.options) { option in
                                Text(option.title).tag(VideoBackdrop?.some(option))
                            }
                        }
                    }
                }

                SwiftUI.ColorPicker("Color", selection: colorBinding, supportsOpacity: false)

                LabeledContent("Custom Image") {
                    Button(customImageName ?? "Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            backdrop = .customImage(url)
                            customImageName = url.lastPathComponent
                        }
                    }
                }

                if case .bundled = backdrop {
                    Text("Bundled wallpapers courtesy of the Recordly project.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Frame") {
                LabeledContent("Padding") {
                    Slider(value: $style.paddingFraction, in: 0...0.30)
                    Text(style.paddingFraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Corner radius") {
                    Slider(value: $style.cornerRadius, in: 0...40)
                    Text("\(Int(style.cornerRadius))")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Shadow") {
                    Slider(value: $style.shadowOpacity, in: 0...1)
                    Text(style.shadowOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }

            Section("Canvas") {
                Picker("Aspect", selection: $style.aspect) {
                    ForEach(CanvasAspect.allCases) { aspect in
                        Text(aspect.title).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding(8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trim")
                    .font(.headline)
                Spacer()
                Button {
                    showStylePopover.toggle()
                } label: {
                    Label("Style", systemImage: "paintbrush")
                }
                .popover(isPresented: $showStylePopover, arrowEdge: .bottom) {
                    stylePopover
                }
            }

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
        let suffix = backdrop == nil ? "-trimmed.mov" : "-styled.mov"
        panel.nameFieldStringValue = item.fileURL.deletingPathExtension().lastPathComponent + suffix
        panel.allowedContentTypes = [.quickTimeMovie, .mpeg4Movie]
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            if let backdrop {
                _ = try await VideoCompositor.composite(
                    sourceURL: item.fileURL,
                    outputURL: outURL,
                    backdrop: backdrop,
                    backdropScreen: NSScreen.main,
                    cursor: nil,
                    trimStart: trimStart,
                    trimEnd: trimEnd,
                    style: style
                )
            } else {
                _ = try await TrimExporter.export(
                    sourceURL: item.fileURL,
                    outputURL: outURL,
                    start: trimStart,
                    end: trimEnd
                )
            }
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
