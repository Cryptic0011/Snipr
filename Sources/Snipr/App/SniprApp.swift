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

        if let logoURL = Bundle.module.url(forResource: "SniprLogo", withExtension: "png"),
           let image = NSImage(contentsOf: logoURL) {
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
            LabeledContent("Screen Recording") {
                Text(PermissionService.hasScreenRecordingAccess ? "Allowed" : "Required")
                    .foregroundStyle(PermissionService.hasScreenRecordingAccess ? .green : .orange)
            }

            LabeledContent("Capture Folder") {
                Text(model.captureStore.rootDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Open Screen Recording Settings") {
                PermissionService.openScreenRecordingSettings()
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 560)
    }
}
