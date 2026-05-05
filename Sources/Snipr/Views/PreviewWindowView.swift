import SwiftUI

struct PreviewWindowView: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    coordinator.copy(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    coordinator.saveAs(item)
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down")
                }

                Button {
                    coordinator.reveal(item)
                } label: {
                    Label("Reveal", systemImage: "finder")
                }

                Button(role: .destructive) {
                    coordinator.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding(12)
            .background(.bar)

            GeometryReader { proxy in
                if let image = NSImage(contentsOf: item.fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(Color.black.opacity(0.84))
                } else {
                    ContentUnavailableView("Image Missing", systemImage: "photo.badge.exclamationmark")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            HStack {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(item.dimensionsText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
        }
    }
}
