import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderButton: View {
    let binding: HotKeyBinding
    let isRecording: Bool
    let isEnabled: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onRecord: (HotKeyBinding) -> Void

    var body: some View {
        ZStack {
            Button {
                if isRecording {
                    onStopRecording()
                } else {
                    onStartRecording()
                }
            } label: {
                Text(isRecording ? "Press keys..." : binding.displayText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 116)
            }
            .disabled(!isEnabled)

            if isRecording {
                HotKeyCaptureView(
                    onRecord: { recorded in
                        onRecord(recorded)
                        onStopRecording()
                    },
                    onCancel: onStopRecording
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
    }
}

private struct HotKeyCaptureView: NSViewRepresentable {
    let onRecord: (HotKeyBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CaptureNSView: NSView {
        var onRecord: ((HotKeyBinding) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                onCancel?()
                return
            }

            let modifiers = HotKeyFormatter.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                NSSound.beep()
                return
            }

            onRecord?(
                HotKeyBinding(
                    keyCode: UInt32(event.keyCode),
                    modifiers: modifiers,
                    isEnabled: true
                )
            )
        }
    }
}
