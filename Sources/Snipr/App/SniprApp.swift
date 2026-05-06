import SwiftUI

@main
struct SniprApp: App {
    @NSApplicationDelegateAdaptor(SniprAppDelegate.self) private var appDelegate
    @State private var model = SniprAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1080, minHeight: 640)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.configure(with: model)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture Area") {
                    model.coordinator.startCaptureArea()
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])

                Button("Open Command Palette") {
                    model.coordinator.showCommandPalette()
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])

                Button("Clear Stack") {
                    model.coordinator.clearStack()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class SniprAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var model: SniprAppModel?
    private var hotKeyService: HotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func configure(with model: SniprAppModel) {
        guard self.model == nil else {
            return
        }

        self.model = model
        installStatusItem(model: model)
        installHotkeys(model: model)
    }

    private func installStatusItem(model: SniprAppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let image = SniprAssets.image(named: "SniprLogoMark") {
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
        } else {
            item.button?.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "Snipr")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Command Palette", action: #selector(openPalette), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear Stack", action: #selector(clearStack), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snipr", action: #selector(quit), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func installHotkeys(model: SniprAppModel) {
        hotKeyService = HotKeyService { [weak model] hotkey in
            switch hotkey {
            case .commandPalette:
                model?.coordinator.showCommandPalette()
            case .captureArea:
                model?.coordinator.startCaptureArea()
            }
        }
        hotKeyService?.registerDefaults()
    }

    @objc private func captureArea() {
        model?.coordinator.startCaptureArea()
    }

    @objc private func openPalette() {
        model?.coordinator.showCommandPalette()
    }

    @objc private func openHistory() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "Snipr" }?.makeKeyAndOrderFront(nil)
    }

    @objc private func clearStack() {
        model?.coordinator.clearStack()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct SettingsView: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    Text(PermissionService.hasScreenRecordingAccess ? "Allowed" : "Required")
                        .foregroundStyle(PermissionService.hasScreenRecordingAccess ? .green : .orange)
                }

                Button("Open Screen Recording Settings") {
                    PermissionService.openScreenRecordingSettings()
                }
            }

            Section("Stack") {
                Toggle("Show stack after capture", isOn: Binding(
                    get: { model.preferences.showStackAfterCapture },
                    set: { model.preferences.showStackAfterCapture = $0 }
                ))

                Toggle("Auto-hide stack", isOn: Binding(
                    get: { model.preferences.autoHideStack },
                    set: { model.preferences.autoHideStack = $0 }
                ))

                LabeledContent("Hide delay") {
                    HStack {
                        Slider(value: Binding(
                            get: { model.preferences.stackAutoHideDelay },
                            set: { model.preferences.stackAutoHideDelay = $0 }
                        ), in: 3...30, step: 1)
                        .frame(width: 180)
                        .disabled(!model.preferences.autoHideStack)

                        Text("\(Int(model.preferences.stackAutoHideDelay))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Toggle("Pause auto-hide while hovered", isOn: Binding(
                    get: { model.preferences.pauseStackAutoHideOnHover },
                    set: { model.preferences.pauseStackAutoHideOnHover = $0 }
                ))
                .disabled(!model.preferences.autoHideStack)

                Toggle("Hide stack after opening annotation", isOn: Binding(
                    get: { model.preferences.hideStackAfterPreview },
                    set: { model.preferences.hideStackAfterPreview = $0 }
                ))

                Button("Reset Stack Defaults") {
                    model.preferences.resetStackDefaults()
                }
            }

            Section("Storage") {
                LabeledContent("Capture Folder") {
                    Text(model.captureStore.rootDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 620)
    }
}
