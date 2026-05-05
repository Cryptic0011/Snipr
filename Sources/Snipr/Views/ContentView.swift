import SwiftUI

struct ContentView: View {
    let model: SniprAppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Actions") {
                    Button {
                        model.coordinator.startCaptureArea()
                    } label: {
                        Label("Capture Area", systemImage: "selection.pin.in.out")
                    }

                    Button {
                        model.coordinator.showCommandPalette()
                    } label: {
                        Label("Command Palette", systemImage: "command")
                    }
                }

                Section("History") {
                    ForEach(model.captureStore.items) { item in
                        Button {
                            model.coordinator.openPreview(for: item)
                        } label: {
                            Label(item.filename, systemImage: "photo")
                                .lineLimit(1)
                        }
                        .contextMenu {
                            CaptureContextMenu(item: item, coordinator: model.coordinator)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 24) {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                VStack(spacing: 8) {
                    Text("Snipr")
                        .font(.largeTitle.weight(.semibold))

                    Text("Local-first capture, stack, and history.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        model.coordinator.startCaptureArea()
                    } label: {
                        Label("Capture Area", systemImage: "selection.pin.in.out")
                    }
                    .keyboardShortcut("4", modifiers: [.command, .shift])

                    Button {
                        model.coordinator.showCommandPalette()
                    } label: {
                        Label("Palette", systemImage: "command")
                    }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
                }

                if !PermissionService.hasScreenRecordingAccess {
                    VStack(spacing: 10) {
                        Label("Screen Recording permission is required for capture.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)

                        Button("Open Screen Recording Settings") {
                            PermissionService.openScreenRecordingSettings()
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if model.captureStore.items.isEmpty {
                    Text("No captures yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(model.captureStore.items.count) local captures")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private var logoImage: NSImage {
        if let url = Bundle.module.url(forResource: "SniprLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "Snipr") ?? NSImage()
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
