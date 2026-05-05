import SwiftUI

struct ThumbnailStackView: View {
    let store: CaptureStore
    let coordinator: WindowCoordinator

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(store.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                ThumbnailView(item: item, coordinator: coordinator)
                    .offset(x: CGFloat(index) * -5, y: CGFloat(index) * 16)
                    .zIndex(Double(10 - index))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

private struct ThumbnailView: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = NSImage(contentsOf: item.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 100)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 160, height: 100)
                    .overlay(Image(systemName: "exclamationmark.triangle"))
            }

            Text(item.dimensionsText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14)))
        .shadow(radius: 14, y: 8)
        .onTapGesture(count: 2) {
            coordinator.openPreview(for: item)
        }
        .contextMenu {
            CaptureContextMenu(item: item, coordinator: coordinator)
        }
    }
}
