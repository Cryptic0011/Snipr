import SwiftUI

struct ContentView: View {
    let model: SniprAppModel

    var body: some View {
        ZStack {
            RaycastBackdrop()

            VStack(spacing: 0) {
                HStack(spacing: 42) {
                    HeroPane(
                        logoImage: logoImage,
                        capturesCount: model.captureStore.items.count,
                        coordinator: model.coordinator
                    )
                    .frame(width: 355, alignment: .leading)

                    DashboardPane(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 52)
                .padding(.top, 62)
                .padding(.bottom, 12)

                BottomStrip(model: model)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)
            }
        }
        .foregroundStyle(.white)
    }

    private var logoImage: NSImage {
        if let url = Bundle.module.url(forResource: "SniprLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "Snipr") ?? NSImage()
    }
}

private struct RaycastBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.045, blue: 0.052)

            RadialGradient(
                colors: [
                    Color(red: 0.72, green: 0.04, blue: 0.28).opacity(0.54),
                    Color(red: 0.22, green: 0.05, blue: 0.44).opacity(0.34),
                    .clear
                ],
                center: .center,
                startRadius: 80,
                endRadius: 560
            )
            .blur(radius: 8)

            LinearGradient(
                colors: [
                    .black.opacity(0.56),
                    .clear,
                    Color(red: 0.24, green: 0.05, blue: 0.06).opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct HeroPane: View {
    let logoImage: NSImage
    let capturesCount: Int
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .shadow(color: .white.opacity(0.16), radius: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Snipr")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(capturesCount == 0 ? "Local capture utility" : "\(capturesCount) captures stored")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Ready for\nclean shots?")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Local captures. One hotkey away.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(4)
                    .lineLimit(3)
            }

            FloatingKeys()
                .frame(height: 145)

            VStack(alignment: .leading, spacing: 10) {
                ActionButton(title: "Capture Area", systemImage: "selection.pin.in.out", shortcut: "⌘⇧4") {
                    coordinator.startCaptureArea()
                }

                ActionButton(title: "Open Palette", systemImage: "command", shortcut: "⌘⇧Space") {
                    coordinator.showCommandPalette()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DashboardPane: View {
    let model: SniprAppModel

    var body: some View {
        VStack(spacing: 14) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unlock the full potential")
                                .font(.system(size: 28, weight: .bold, design: .rounded))

                            Text("Grant access once, then capture without friction.")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.54))
                        }

                        Spacer()

                        Button {
                            model.coordinator.showCommandPalette()
                        } label: {
                            Label("Palette", systemImage: "command")
                        }
                        .buttonStyle(CompactDarkButtonStyle())
                    }

                    VStack(spacing: 0) {
                        PermissionRow(
                            systemImage: "rectangle.dashed",
                            title: "Screen Recording",
                            subtitle: "Allows Snipr to capture selected regions.",
                            isGranted: PermissionService.hasScreenRecordingAccess,
                            actionTitle: PermissionService.hasScreenRecordingAccess ? "Access Granted" : "Open Settings"
                        ) {
                            PermissionService.openScreenRecordingSettings()
                        }

                        DividerLine()

                        PermissionRow(
                            systemImage: "folder",
                            title: "Local Capture Folder",
                            subtitle: "Local PNG storage for your capture stack.",
                            isGranted: true,
                            actionTitle: "Reveal"
                        ) {
                            NSWorkspace.shared.activateFileViewerSelecting([model.captureStore.rootDirectory])
                        }

                        DividerLine()

                        PermissionRow(
                            systemImage: "keyboard",
                            title: "Global Hotkeys",
                            subtitle: "Palette and capture shortcuts are active.",
                            isGranted: true,
                            actionTitle: "Ready"
                        ) {}
                    }
                }
            }
            .frame(minHeight: 286, idealHeight: 304, maxHeight: 324)

            GlassPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Recent Captures")
                            .font(.system(size: 17, weight: .bold))

                        Spacer()

                        Button {
                            model.coordinator.clearStack()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(CompactDarkButtonStyle())
                        .disabled(model.captureStore.items.isEmpty)
                    }

                    if model.captureStore.items.isEmpty {
                        EmptyHistoryView()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(model.captureStore.items.prefix(8)) { item in
                                    CaptureHistoryRow(item: item, coordinator: model.coordinator)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }

            Spacer()

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: isGranted ? "checkmark" : "arrow.up.right")
                    Text(actionTitle)
                }
                .frame(minWidth: 126)
            }
            .buttonStyle(OutlineStatusButtonStyle(isGranted: isGranted))
        }
        .padding(.vertical, 13)
    }
}

private struct CaptureHistoryRow: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        HStack(spacing: 12) {
            if let image = NSImage(contentsOf: item.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 38)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.08))
                    .frame(width: 58, height: 38)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text("\(item.dimensionsText) • \(item.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.46))
            }

            Spacer()

            Button {
                coordinator.openPreview(for: item)
            } label: {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(IconDarkButtonStyle())
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            CaptureContextMenu(item: item, coordinator: coordinator)
        }
        .onTapGesture(count: 2) {
            coordinator.openPreview(for: item)
        }
    }
}

private struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.36))

            Text("Take a capture to start your local stack.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BottomStrip: View {
    let model: SniprAppModel

    var body: some View {
        HStack(spacing: 18) {
            Button {
                model.coordinator.showCommandPalette()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconDarkButtonStyle())

            HStack(spacing: 8) {
                ForEach(0..<11, id: \.self) { index in
                    Capsule()
                        .fill(index == 3 ? Color(red: 1.0, green: 0.37, blue: 0.43) : .white.opacity(0.16))
                        .frame(width: index == 3 ? 54 : 13, height: 4)
                        .shadow(color: index == 3 ? Color.red.opacity(0.8) : .clear, radius: 8)
                }
            }

            Spacer()

            Text("Hit ")
                .foregroundStyle(.white.opacity(0.48))
            + Text("⌘⇧Space")
                .fontWeight(.bold)
            + Text(" for commands")
                .foregroundStyle(.white.opacity(0.48))

            Button {
                model.coordinator.startCaptureArea()
            } label: {
                Text("Capture")
                    .frame(minWidth: 96)
            }
            .buttonStyle(PrimaryRaycastButtonStyle())
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.105, green: 0.11, blue: 0.12).opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.07)))
        )
    }
}

private struct FloatingKeys: View {
    var body: some View {
        ZStack {
            KeyCap(label: "⌘", width: 92, height: 72)
                .rotationEffect(.degrees(-17))
                .offset(x: -70, y: -30)
                .opacity(0.38)
                .blur(radius: 2)

            KeyCap(label: "⇧", width: 92, height: 72)
                .rotationEffect(.degrees(13))
                .offset(x: 86, y: -36)
                .opacity(0.28)
                .blur(radius: 2)

            KeyCap(label: "⌘", width: 96, height: 74)
                .rotationEffect(.degrees(2))
                .offset(x: -38, y: 16)

            KeyCap(label: "space", width: 190, height: 76)
                .rotationEffect(.degrees(-9))
                .offset(x: 74, y: 30)
        }
    }
}

private struct KeyCap: View {
    let label: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.07, blue: 0.17),
                        Color(red: 0.06, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.58), radius: 12, y: 8)
            .frame(width: width, height: height)
            .overlay(
                Text(label)
                    .font(.system(size: label == "space" ? 23 : 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            )
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.46))
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.06), Color(red: 0.4, green: 0.05, blue: 0.08).opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            )
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct CompactDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.05 : 0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct IconDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.86))
            .frame(width: 28, height: 28)
            .background(.white.opacity(configuration.isPressed ? 0.05 : 0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct PrimaryRaycastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.96))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.36, green: 0.2, blue: 0.22).opacity(configuration.isPressed ? 0.75 : 1.0))
            )
    }
}

private struct OutlineStatusButtonStyle: ButtonStyle {
    let isGranted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.94))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isGranted ? .white.opacity(0.025) : Color(red: 0.45, green: 0.14, blue: 0.16).opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isGranted ? .white.opacity(0.11) : Color(red: 1.0, green: 0.36, blue: 0.4).opacity(0.3))
                    )
            )
    }
}

struct CaptureContextMenu: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        Button("Preview") {
            coordinator.openPreview(for: item)
        }

        Button("Copy Image") {
            coordinator.copy(item)
        }

        Button("Save As…") {
            coordinator.saveAs(item)
        }

        Button("Reveal in Finder") {
            coordinator.reveal(item)
        }

        Divider()

        Button("Delete", role: .destructive) {
            coordinator.delete(item)
        }
    }
}
