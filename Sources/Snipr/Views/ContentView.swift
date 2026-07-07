import SwiftUI

/// Brand palette shared with the landing page: charcoal + brass, from the mark.
private enum Brand {
    static let brass = Color(red: 0.804, green: 0.667, blue: 0.329)      // #cdaa54
    static let brassDeep = Color(red: 0.35, green: 0.27, blue: 0.12)
    static let charcoal = Color(red: 0.149, green: 0.149, blue: 0.141)   // #262624
    static let inkOnBrass = Color(red: 0.122, green: 0.118, blue: 0.102) // #1f1e1a
}

struct ContentView: View {
    let model: SniprAppModel
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        ZStack {
            RaycastBackdrop()

            VStack(spacing: 0) {
                HStack(spacing: 28) {
                    HeroPane(
                        logoMarkImage: logoMarkImage,
                        wordmarkImage: wordmarkImage,
                        capturesCount: model.captureStore.items.count,
                        coordinator: model.coordinator
                    )
                    .frame(width: 310, alignment: .leading)

                    DashboardPane(model: model, selectedTab: selectedTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 36)
                .padding(.top, 44)
                .padding(.bottom, 12)

                BottomStrip(model: model, selectedTab: $selectedTab)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)
            }
        }
        .foregroundStyle(.white)
    }

    private var logoMarkImage: NSImage {
        if let image = SniprAssets.image(named: "SniprLogoMark") {
            return image
        }

        return NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "Snipr") ?? NSImage()
    }

    private var wordmarkImage: NSImage {
        if let image = SniprAssets.image(named: "SniprWordmark") {
            return image
        }

        return NSImage()
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "sparkles"
        case .settings:
            "gear"
        }
    }

    var next: DashboardTab {
        let tabs = Self.allCases
        let index = tabs.firstIndex(of: self) ?? 0
        return tabs[(index + 1) % tabs.count]
    }

    var previous: DashboardTab {
        let tabs = Self.allCases
        let index = tabs.firstIndex(of: self) ?? 0
        return tabs[(index + tabs.count - 1) % tabs.count]
    }
}

private struct RaycastBackdrop: View {
    var body: some View {
        ZStack {
            Brand.charcoal

            RadialGradient(
                colors: [
                    Brand.brass.opacity(0.16),
                    Brand.brassDeep.opacity(0.14),
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
                    Brand.brassDeep.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct HeroPane: View {
    let logoMarkImage: NSImage
    let wordmarkImage: NSImage
    let capturesCount: Int
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: logoMarkImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .shadow(color: .white.opacity(0.16), radius: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: wordmarkImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 34, alignment: .leading)

                    Text(capturesCount == 0 ? "Local capture utility" : "\(capturesCount) captures stored")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Ready for\nclean shots?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Local captures. One hotkey away.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(4)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 8) {
                ActionButton(title: "Capture Area", systemImage: "selection.pin.in.out") {
                    coordinator.startCaptureArea()
                }

                ActionButton(title: "Record Area", systemImage: "record.circle") {
                    coordinator.startScreenRecordingArea()
                }

                ActionButton(title: "OCR Selection", systemImage: "textformat.123") {
                    coordinator.startOCR()
                }

                ActionButton(title: "Pick Color", systemImage: "eyedropper") {
                    coordinator.startColorPick()
                }

                ActionButton(title: "Open Palette", systemImage: "command") {
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
    let selectedTab: DashboardTab

    var body: some View {
        VStack(spacing: 14) {
            switch selectedTab {
            case .overview:
                RecentCapturesPanel(model: model)
                    .frame(maxHeight: .infinity)
            case .settings:
                SettingsPanel(model: model)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct RecentCapturesPanel: View {
    let model: SniprAppModel

    var body: some View {
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

private struct CaptureHistoryRow: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnailView(
                item: item,
                size: CGSize(width: 58, height: 38),
                cornerRadius: 5
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text("\(item.detailText) • \(item.createdAt.formatted(date: .omitted, time: .shortened))")
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

private struct SettingsPanel: View {
    let model: SniprAppModel

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 17, weight: .bold))

                VStack(alignment: .leading, spacing: 16) {
                    SettingsLink {
                        Label("Open Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryRaycastButtonStyle())

                    Text("Configure capture, recording, hotkeys, and more.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.46))
                }

                Divider()
                    .overlay(.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Snipr")
                        .font(.system(size: 13, weight: .bold))
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer()
            }
        }
    }
}

private struct BottomStrip: View {
    let model: SniprAppModel
    @Binding var selectedTab: DashboardTab

    var body: some View {
        HStack(spacing: 10) {
            Button {
                selectedTab = selectedTab.previous
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconDarkButtonStyle())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DashboardTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                        .buttonStyle(TabPillButtonStyle(isSelected: selectedTab == tab))
                    }
                }
            }

            Spacer()

            Button {
                selectedTab = selectedTab.next
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(IconDarkButtonStyle())

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
                .fill(Color(red: 0.125, green: 0.125, blue: 0.118).opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.07)))
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
                            colors: [.white.opacity(0.06), Brand.brass.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            )
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
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
            .foregroundStyle(Brand.inkOnBrass.opacity(configuration.isPressed ? 0.72 : 1.0))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Brand.brass.opacity(configuration.isPressed ? 0.78 : 1.0))
            )
    }
}

private struct TabPillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(
                isSelected
                    ? Brand.brass.opacity(configuration.isPressed ? 0.72 : 1.0)
                    : .white.opacity(configuration.isPressed ? 0.64 : 0.56)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Brand.brass.opacity(0.14) : .white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected ? Brand.brass.opacity(0.4) : .white.opacity(0.06))
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

        Button(item.mediaType == .image ? "Copy Image" : "Copy Movie") {
            coordinator.copy(item)
        }

        Button("Save As…") {
            coordinator.saveAs(item)
        }

        Button("Reveal in Finder") {
            coordinator.reveal(item)
        }

        if item.mediaType == .video {
            Button("Export as GIF…") {
                coordinator.exportGIF(item)
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            coordinator.delete(item)
        }
    }
}
