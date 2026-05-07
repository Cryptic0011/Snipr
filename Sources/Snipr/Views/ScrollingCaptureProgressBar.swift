import SwiftUI

/// Pure model for the progress HUD — separated from the SwiftUI view so the
/// "captured vertical pixels" math is unit-testable without booting the UI.
@Observable
@MainActor
final class ScrollingCaptureProgress {
    private(set) var capturedPixels: Int = 0
    private(set) var isRunning: Bool = false

    func start() {
        capturedPixels = 0
        isRunning = true
    }

    func update(capturedPixels: Int) {
        // Monotonic — collectors append frame heights so the cumulative
        // value never decreases. Defensive max() guards against an out-of-
        // order delivery from the dispatch queue.
        self.capturedPixels = max(self.capturedPixels, capturedPixels)
    }

    func finish() {
        isRunning = false
    }

    /// Display text for the HUD label. Round to nearest 10px — feels less
    /// jittery than an exact pixel count rolling at 8–10 fps.
    var displayText: String {
        let rounded = (capturedPixels / 10) * 10
        return "Scrolling capture · \(rounded) px"
    }
}

/// Minimalist top-of-screen progress bar shown while a scrolling capture is
/// in progress. Two affordances: a "Stop" button to commit and a tally of
/// captured vertical pixels. Click stop, see the result land in the stack.
struct ScrollingCaptureProgressBar: View {
    let progress: ScrollingCaptureProgress
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
                .tint(.white)

            Text(progress.displayText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .frame(minWidth: 220, alignment: .leading)

            Button {
                onStop()
            } label: {
                Text("Stitch Now")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help("Finish and stitch")

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(0.78))
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Cancel scrolling capture")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }
}
