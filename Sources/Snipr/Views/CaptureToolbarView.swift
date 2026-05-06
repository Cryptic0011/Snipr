import SwiftUI

enum CaptureToolbarMode: String, CaseIterable, Identifiable {
    case screenshotArea
    case recordArea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshotArea:
            "Capture Area"
        case .recordArea:
            "Record Area"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshotArea:
            "selection.pin.in.out"
        case .recordArea:
            "rectangle.dashed.badge.record"
        }
    }

    var primaryTitle: String {
        switch self {
        case .screenshotArea:
            "Capture"
        case .recordArea:
            "Record"
        }
    }
}

struct CaptureToolbarView: View {
    @State private var selectedMode: CaptureToolbarMode = .screenshotArea

    let onCancel: () -> Void
    let onOptions: () -> Void
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

            HStack(spacing: 4) {
                ForEach(CaptureToolbarMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 34)
                    }
                    .buttonStyle(CaptureToolbarIconButtonStyle(isSelected: selectedMode == mode))
                    .help(mode.title)
                }
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)

            Button {
                onOptions()
            } label: {
                HStack(spacing: 4) {
                    Text("Options")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(height: 34)
                .padding(.horizontal, 10)
            }
            .buttonStyle(CaptureToolbarTextButtonStyle())

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
}

private struct CaptureToolbarIconButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(configuration.isPressed ? 0.48 : 0.78))
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
