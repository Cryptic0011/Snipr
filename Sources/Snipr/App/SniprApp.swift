import SwiftUI

@main
struct SniprApp: App {
    @NSApplicationDelegateAdaptor(SniprAppDelegate.self) private var appDelegate

    var body: some Scene {
        // The dashboard is a delegate-owned NSWindow (see showDashboard), not
        // a WindowGroup: SwiftUI destroys a closed WindowGroup window and an
        // accessory app has no Dock icon or menu to summon it back, which
        // left "Show Dashboard" dead after the first close.
        Settings {
            SettingsView(model: appDelegate.model)
        }
        // No keyboardShortcut on these: the same shortcuts are registered
        // globally through HotKeyService from the user's bindings, and
        // hard-coded menu copies would show stale hints after a rebind.
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Capture Toolbar") {
                    appDelegate.model.coordinator.showCaptureToolbar()
                }

                Button("Capture Area") {
                    appDelegate.model.coordinator.startCaptureArea()
                }

                Button("Record Screen Area") {
                    appDelegate.model.coordinator.startScreenRecordingArea()
                }

                Button("Open Command Palette") {
                    appDelegate.model.coordinator.showCommandPalette()
                }

                Button("Clear Stack") {
                    appDelegate.model.coordinator.clearStack()
                }
            }
        }
    }
}

@MainActor
final class SniprAppDelegate: NSObject, NSApplicationDelegate {
    let model = SniprAppModel()
    private var statusItem: NSStatusItem?
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem(model: model)
        model.installHotkeys()
        model.coordinator.onOpenMainWindow = { [weak self] in
            self?.showDashboard()
        }
        showDashboard()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Create-once dashboard window. `isReleasedWhenClosed = false` means the
    /// red close button only hides it, so every later "Show Dashboard" can
    /// bring the same window back.
    func showDashboard() {
        NSApp.activate(ignoringOtherApps: true)

        if let dashboardWindow {
            dashboardWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Snipr"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 780, height: 480)
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 780, minHeight: 480)
                .preferredColorScheme(.dark)
        )
        SniprDiagnostics.disableRestoration(for: window)
        window.center()
        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
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
        menu.addItem(NSMenuItem(title: "Show Dashboard", action: #selector(openHistory), keyEquivalent: ""))
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
        model.coordinator.startCaptureArea()
    }

    @objc private func openCaptureToolbar() {
        model.coordinator.showCaptureToolbar()
    }

    @objc private func recordScreenArea() {
        model.coordinator.startScreenRecordingArea()
    }

    @objc private func openPalette() {
        model.coordinator.showCommandPalette()
    }

    @objc private func openHistory() {
        showDashboard()
    }

    @objc private func clearStack() {
        model.coordinator.clearStack()
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
