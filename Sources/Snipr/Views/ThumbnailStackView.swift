import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailStackView: View {
    let store: CaptureStore
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Snipr Stack")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button {
                    coordinator.setThumbnailStackPinned(!coordinator.isThumbnailStackPinned)
                } label: {
                    Image(systemName: coordinator.isThumbnailStackPinned ? "pin.fill" : "pin")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(StackIconButtonStyle(isActive: coordinator.isThumbnailStackPinned))
                .help(coordinator.isThumbnailStackPinned ? "Unpin stack" : "Pin stack")

                Text("\(store.items.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())

                Button {
                    coordinator.hideThumbnailStack()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(StackIconButtonStyle(isActive: false))
                .help("Hide stack")
            }

            Text(coordinator.isThumbnailStackPinned ? "Pinned until you close it" : "Drag a capture out or double-click to annotate")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.44))

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.items.prefix(12)) { item in
                        ThumbnailView(item: item, coordinator: coordinator)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .background(Color(red: 0.055, green: 0.055, blue: 0.065).opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { isHovered in
            coordinator.setThumbnailStackHovering(isHovered)
        }
    }
}

private struct StackIconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : .white.opacity(0.58))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.white.opacity(0.16) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
    }
}

private struct ThumbnailView: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.mediaType == .image, let image = NSImage(contentsOf: item.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 188, height: 106)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 188, height: 106)
                    .overlay(
                        Image(systemName: item.mediaType == .video ? "play.fill" : "exclamationmark.triangle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white.opacity(0.74))
                    )
            }

            HStack {
                Text(item.detailText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 7)
        }
        .onDrag {
            let provider = NSItemProvider()
            provider.suggestedName = item.filename
            provider.registerFileRepresentation(
                forTypeIdentifier: item.mediaType == .image ? UTType.png.identifier : UTType.quickTimeMovie.identifier,
                fileOptions: [.openInPlace],
                visibility: .all
            ) { completion in
                completion(item.fileURL, true, nil)
                return nil
            }
            return provider
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
