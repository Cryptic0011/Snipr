import SwiftUI

struct RecordingHUDView: View {
    let startedAt: Date
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.4), radius: 3)

            Text(elapsedText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 62, alignment: .leading)

            Button {
                onStop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(RecordingHUDButtonStyle(isDestructive: false))

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RecordingHUDButtonStyle(isDestructive: true))
            .help("Discard recording")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.84))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16)))
        )
        .onReceive(timer) { now = $0 }
    }

    private var elapsedText: String {
        let elapsed = Int(now.timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

private struct RecordingHUDButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.96))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isDestructive ? Color.white.opacity(0.08) : Color.red.opacity(configuration.isPressed ? 0.54 : 0.72))
            )
    }
}
