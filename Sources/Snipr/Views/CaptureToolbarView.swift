import SwiftUI

enum CaptureToolbarMode: String, CaseIterable, Identifiable {
    case captureScreen
    case captureWindow
    case captureSelection
    case recordScreen
    case recordWindow
    case recordSelection
    case ocrSelection
    case pickColor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureScreen:
            "Capture Entire Screen"
        case .captureWindow:
            "Capture Window"
        case .captureSelection:
            "Capture Selected Portion"
        case .recordScreen:
            "Record Entire Screen"
        case .recordWindow:
            "Record Window"
        case .recordSelection:
            "Record Selected Portion"
        case .ocrSelection:
            "OCR Selected Region"
        case .pickColor:
            "Pick a Pixel Color"
        }
    }

    var systemImage: String {
        switch self {
        case .captureScreen:
            "display"
        case .captureWindow:
            "macwindow"
        case .captureSelection:
            "selection.pin.in.out"
        case .recordScreen:
            "record.circle"
        case .recordWindow:
            "inset.filled.rectangle.badge.record"
        case .recordSelection:
            "rectangle.dashed.badge.record"
        case .ocrSelection:
            "textformat.123"
        case .pickColor:
            "eyedropper"
        }
    }

    var primaryTitle: String {
        switch self {
        case .captureScreen, .captureWindow, .captureSelection:
            "Capture"
        case .recordScreen, .recordWindow, .recordSelection:
            "Record"
        case .ocrSelection:
            "OCR"
        case .pickColor:
            "Sample"
        }
    }

    var isEnabled: Bool {
        true
    }
}

struct CaptureToolbarView: View {
    @State private var selectedMode: CaptureToolbarMode = .captureSelection

    let onCancel: () -> Void
    let onExecute: (CaptureToolbarMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(CaptureToolbarIconButtonStyle(isSelected: false))
            .help("Close")

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 6)

            toolbarButtons(for: [.captureScreen, .captureWindow, .captureSelection])

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 6)

            toolbarButtons(for: [.recordScreen, .recordWindow, .recordSelection])

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 6)

            toolbarButtons(for: [.ocrSelection, .pickColor])

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 6)

            Button {
                onExecute(selectedMode)
            } label: {
                Text(selectedMode.primaryTitle)
                    .frame(minWidth: 72, minHeight: 34)
            }
            .buttonStyle(CaptureToolbarPrimaryButtonStyle())
            .disabled(!selectedMode.isEnabled)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.34)))
    }

    private func toolbarButtons(for modes: [CaptureToolbarMode]) -> some View {
        HStack(spacing: 4) {
            ForEach(modes) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 34)
                        .overlay(alignment: .bottomTrailing) {
                            if !mode.isEnabled {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.42))
                                    .padding(3)
                            }
                        }
                }
                .buttonStyle(CaptureToolbarIconButtonStyle(isSelected: selectedMode == mode, isEnabled: mode.isEnabled))
                .help(mode.isEnabled ? mode.title : "\(mode.title) coming soon")
            }
        }
    }
}

private struct CaptureToolbarIconButtonStyle: ButtonStyle {
    let isSelected: Bool
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(isEnabled ? (configuration.isPressed ? 0.48 : 0.78) : 0.34))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.black.opacity(0.12) : Color.black.opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

private struct CaptureToolbarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(configuration.isPressed ? 0.48 : 0.78))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

private struct CaptureToolbarPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(configuration.isPressed ? 0.52 : 0.82))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
    }
}
