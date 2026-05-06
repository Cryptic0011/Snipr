import SwiftUI

struct MediaThumbnailView: View {
    let item: CaptureItem
    let size: CGSize
    let cornerRadius: CGFloat

    @State private var videoThumbnail: NSImage?

    var body: some View {
        ZStack {
            if item.mediaType == .image, let image = NSImage(contentsOf: item.fileURL) {
                thumbnailImage(image)
            } else if item.mediaType == .video, let videoThumbnail {
                thumbnailImage(videoThumbnail)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.08))
                    .frame(width: size.width, height: size.height)
                    .overlay(Image(systemName: item.mediaType == .video ? "play.fill" : "photo").foregroundStyle(.secondary))
            }

            if item.mediaType == .video {
                Circle()
                    .fill(Color.black.opacity(0.62))
                    .frame(width: min(36, size.height * 0.62), height: min(36, size.height * 0.62))
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: min(15, size.height * 0.26), weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .offset(x: 1)
                    )
            }
        }
        .task(id: item.fileURL) {
            guard item.mediaType == .video else {
                return
            }

            videoThumbnail = VideoThumbnailProvider.thumbnail(
                for: item.fileURL,
                maximumSize: CGSize(width: size.width * 2, height: size.height * 2)
            )
        }
    }

    private func thumbnailImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
