import SwiftUI

struct RecordingRegionFrameView: View {
    let size: CGSize
    let padding: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.red.opacity(0.85), lineWidth: 2)
                .shadow(color: .red.opacity(0.3), radius: 2)
                .padding(padding)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)

                Text("\(Int(size.width)) × \(Int(size.height))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .overlay(Capsule().stroke(Color.red.opacity(0.44)))
            )
            .padding(padding + 8)
        }
        .allowsHitTesting(false)
    }
}
