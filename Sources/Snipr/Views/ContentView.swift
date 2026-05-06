import SwiftUI

struct ContentView: View {
    let model: SniprAppModel
    @State private var selectedTab: DashboardTab = .overview
    @State private var permissionRefreshTick = 0

    var body: some View {
        ZStack {
            RaycastBackdrop()

            VStack(spacing: 0) {
                HStack(spacing: 42) {
                    HeroPane(
                        logoMarkImage: logoMarkImage,
                        wordmarkImage: wordmarkImage,
                        capturesCount: model.captureStore.items.count,
                        coordinator: model.coordinator
                    )
                    .frame(width: 355, alignment: .leading)

                    DashboardPane(model: model, selectedTab: selectedTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 52)
                .padding(.top, 62)
                .padding(.bottom, 12)

                BottomStrip(model: model, selectedTab: $selectedTab)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)
            }
        }
        .foregroundStyle(.white)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                permissionRefreshTick += 1
                _ = permissionRefreshTick
            }
        }
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
    case captures
    case permissions
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .captures:
            "Captures"
        case .permissions:
            "Permissions"
        case .storage:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "sparkles"
        case .captures:
            "photo.stack"
        case .permissions:
            "lock.shield"
        case .storage:
            "gearshape"
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
    let logoMarkImage: NSImage
    let wordmarkImage: NSImage
    let capturesCount: Int
    let coordinator: WindowCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                Image(nsImage: logoMarkImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .shadow(color: .white.opacity(0.16), radius: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: wordmarkImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 126, height: 42, alignment: .leading)

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

            VStack(alignment: .leading, spacing: 10) {
                ActionButton(title: "Capture Area", systemImage: "selection.pin.in.out") {
                    coordinator.startCaptureArea()
                }

                ActionButton(title: "Record Area", systemImage: "record.circle") {
                    coordinator.startScreenRecordingArea()
                }

                ActionButton(title: "Open Palette", systemImage: "command") {
                    coordinator.showCommandPalette()
                }
            }

            GlassMiniCard(
                title: "Customize your flow",
                subtitle: "Use Snipr from the palette, menu bar, or your preferred shortcut launcher."
            )

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
                PermissionsPanel(model: model, compact: true)
                    .frame(minHeight: 286, idealHeight: 304, maxHeight: 324)
                RecentCapturesPanel(model: model)
            case .captures:
                RecentCapturesPanel(model: model)
                    .frame(maxHeight: .infinity)
            case .permissions:
                PermissionsPanel(model: model, compact: false)
                    .frame(maxHeight: .infinity)
            case .storage:
                StoragePanel(model: model)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct PermissionsPanel: View {
    let model: SniprAppModel
    let compact: Bool

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: compact ? 20 : 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unlock the full potential")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Grant only the access needed for local capture workflows.")
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
                        subtitle: "Required to capture selected screen regions.",
                        isGranted: PermissionService.hasScreenRecordingAccess,
                        actionTitle: PermissionService.hasScreenRecordingAccess ? "Access Granted" : "Open Settings"
                    ) {
                        PermissionService.openScreenRecordingSettings()
                    }

                    DividerLine()

                    PermissionRow(
                        systemImage: "figure.wave",
                        title: "Accessibility",
                        subtitle: "Optional for advanced automation and future window-aware capture.",
                        isGranted: PermissionService.hasAccessibilityAccess,
                        actionTitle: PermissionService.hasAccessibilityAccess ? "Access Granted" : "Request Access"
                    ) {
                        if !PermissionService.requestAccessibilityAccess() {
                            PermissionService.openAccessibilitySettings()
                        }
                    }

                    DividerLine()

                    PermissionRow(
                        systemImage: "folder",
                        title: "Local Capture Folder",
                        subtitle: "PNG history stays on this Mac.",
                        isGranted: true,
                        actionTitle: "Reveal"
                    ) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.captureStore.rootDirectory])
                    }
                }
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

private struct StoragePanel: View {
    let model: SniprAppModel

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Tune stack behavior and manage the local capture folder.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))

                VStack(spacing: 0) {
                    StorageRow(title: "More Settings", value: "Open full preferences and hotkeys", systemImage: "gearshape", actionTitle: "Open") {
                        model.coordinator.openSettingsWindow()
                    }

                    DividerLine()

                    StorageRow(title: "Capture Folder", value: model.captureStore.rootDirectory.path, systemImage: "folder", actionTitle: "Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.captureStore.rootDirectory])
                    }

                    DividerLine()

                    StorageRow(title: "Stored Captures", value: "\(model.captureStore.items.count)", systemImage: "photo.stack", actionTitle: "Show") {
                        model.coordinator.showThumbnailStack()
                    }

                    DividerLine()

                    StorageRow(
                        title: "Stack Behavior",
                        value: stackBehaviorSummary,
                        systemImage: "timer",
                        actionTitle: model.preferences.autoHideStack ? "Disable" : "Enable"
                    ) {
                        model.preferences.autoHideStack.toggle()
                    }

                    DividerLine()

                    StorageRow(title: "Clear Local Stack", value: "Remove capture history and files", systemImage: "trash", actionTitle: "Clear") {
                        model.coordinator.clearStack()
                    }
                }
            }
        }
    }

    private var stackBehaviorSummary: String {
        guard model.preferences.showStackAfterCapture else {
            return "Hidden after capture"
        }

        guard model.preferences.autoHideStack else {
            return "Stays visible until closed"
        }

        let hoverText = model.preferences.pauseStackAutoHideOnHover ? ", hover pauses" : ""
        return "Hides after \(Int(model.preferences.stackAutoHideDelay))s\(hoverText)"
    }
}

private struct StorageRow: View {
    let title: String
    let value: String
    let systemImage: String
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

                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(OutlineStatusButtonStyle(isGranted: true))
        }
        .padding(.vertical, 13)
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
                .fill(Color(red: 0.105, green: 0.11, blue: 0.12).opacity(0.9))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct GlassMiniCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 15, weight: .bold))

            Text(subtitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
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

private struct TabPillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.64 : isSelected ? 0.96 : 0.56))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color(red: 0.35, green: 0.17, blue: 0.2).opacity(0.96) : .white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected ? Color(red: 1.0, green: 0.38, blue: 0.44).opacity(0.36) : .white.opacity(0.06))
                    )
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

        Button(item.mediaType == .image ? "Copy Image" : "Copy Movie") {
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
