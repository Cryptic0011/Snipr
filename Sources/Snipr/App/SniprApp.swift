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
                Button("Open Capture Toolbar") {
                    model.coordinator.showCaptureToolbar()
                }
                .keyboardShortcut("5", modifiers: [.command, .shift])

                Button("Capture Area") {
                    model.coordinator.startCaptureArea()
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])

                Button("Record Screen Area") {
                    model.coordinator.startScreenRecordingArea()
                }
                .keyboardShortcut("6", modifiers: [.command, .shift])

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
        model.installHotkeys()
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
        menu.addItem(NSMenuItem(title: "Open Capture Toolbar", action: #selector(openCaptureToolbar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Record Screen Area", action: #selector(recordScreenArea), keyEquivalent: ""))
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

    @objc private func captureArea() {
        model?.coordinator.startCaptureArea()
    }

    @objc private func openCaptureToolbar() {
        model?.coordinator.showCaptureToolbar()
    }

    @objc private func recordScreenArea() {
        model?.coordinator.startScreenRecordingArea()
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

/// Settings UI helper. The picker needs a `Hashable & CaseIterable` choice;
/// `CaptureFormat` carries quality so we wrap it in a tagged enum just for
/// presentation. Quality picks the format-default (0.85) when the user
/// switches.
enum CaptureFormatChoice: String, Hashable, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var format: CaptureFormat {
        switch self {
        case .png: .png
        case .jpeg: .jpeg(quality: 0.85)
        case .heic: .heic(quality: 0.85)
        }
    }

    init(format: CaptureFormat) {
        switch format {
        case .png: self = .png
        case .jpeg: self = .jpeg
        case .heic: self = .heic
        }
    }
}

/// Phase 4 reorganization — every existing setting still lives behind its
/// own tab. Behavior is unchanged; only the shell is rewritten.
struct SettingsView: View {
    let model: SniprAppModel

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }

            CaptureSettingsTab(model: model)
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }

            RecordingSettingsTab(model: model)
                .tabItem { Label("Recording", systemImage: "record.circle") }

            AnnotationSettingsTab(model: model)
                .tabItem { Label("Annotation", systemImage: "pencil.tip") }

            HotkeysSettingsTab(model: model)
                .tabItem { Label("Hotkeys", systemImage: "command") }

            StorageSettingsTab(model: model)
                .tabItem { Label("Storage", systemImage: "internaldrive") }

            AdvancedSettingsTab(model: model)
                .tabItem { Label("Advanced", systemImage: "wand.and.stars") }
        }
        .frame(width: 640, height: 540)
    }
}
