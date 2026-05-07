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
private enum CaptureFormatChoice: String, Hashable, CaseIterable, Identifiable {
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

            Section("Capture") {
                Toggle("Copy to clipboard on capture", isOn: Binding(
                    get: { model.preferences.copyToClipboardOnCapture },
                    set: { model.preferences.copyToClipboardOnCapture = $0 }
                ))

                Toggle("Save to disk", isOn: Binding(
                    get: { model.preferences.saveToDiskOnCapture },
                    set: { model.preferences.saveToDiskOnCapture = $0 }
                ))

                LabeledContent("Format") {
                    Picker("Format", selection: Binding(
                        get: { CaptureFormatChoice(format: model.preferences.captureFormat) },
                        set: { model.preferences.captureFormat = $0.format }
                    )) {
                        ForEach(CaptureFormatChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                LabeledContent("Filename Template") {
                    TextField("Template", text: Binding(
                        get: { model.preferences.captureFilenameTemplate },
                        set: { model.preferences.captureFilenameTemplate = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
                }

                Text("Tokens: {date}, {time}, {app}, {window}, {w}, {h}, {seq}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Record system audio", isOn: Binding(
                    get: { model.preferences.recordSystemAudio },
                    set: { model.preferences.recordSystemAudio = $0 }
                ))
                Text("Mixes desktop audio into the recording. Microphone capture is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Annotation") {
                LabeledContent("Available Tools") {
                    Text(AnnotationKind.allCases.map(\.title).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Color Output Format") {
                    Picker("Color Output Format", selection: Binding(
                        get: { model.preferences.colorOutputFormat },
                        set: { model.preferences.colorOutputFormat = $0 }
                    )) {
                        ForEach(ColorOutputFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            HotKeysSettingsSection(model: model)

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

private struct HotKeysSettingsSection: View {
    let model: SniprAppModel
    @State private var recordingAction: SniprHotKeyAction?
    @State private var conflictMessage: String?

    var body: some View {
        Section("Hotkeys") {
            ForEach(SniprHotKeyAction.allCases) { action in
                HotKeySettingsRow(
                    action: action,
                    binding: model.preferences.binding(for: action),
                    registrationFailure: model.registrationFailure(for: action),
                    isRecording: recordingAction == action,
                    conflictMessage: conflictMessage(for: action),
                    onEnabledChanged: { isEnabled in
                        var binding = model.preferences.binding(for: action)
                        binding.isEnabled = isEnabled
                        save(binding, for: action)
                    },
                    onStartRecording: {
                        conflictMessage = nil
                        recordingAction = action
                    },
                    onStopRecording: {
                        recordingAction = nil
                    },
                    onRecord: { binding in
                        save(binding, for: action)
                    }
                )
            }

            HStack {
                Button("Reset Hotkey Defaults") {
                    conflictMessage = nil
                    model.preferences.resetHotKeyDefaults()
                    model.reinstallHotkeys()
                }

                Spacer()
            }
        }
    }

    private func save(_ binding: HotKeyBinding, for action: SniprHotKeyAction) {
        guard action.isAvailable else {
            return
        }

        if let conflict = model.preferences.conflictingAction(for: action, binding: binding) {
            conflictMessage = "\(action.title) conflicts with \(conflict.title)."
            return
        }

        conflictMessage = nil
        model.preferences.setHotKeyBinding(binding, for: action)
        model.reinstallHotkeys()
    }

    private func conflictMessage(for action: SniprHotKeyAction) -> String? {
        guard let conflictMessage, conflictMessage.hasPrefix(action.title) else {
            return nil
        }

        return conflictMessage
    }
}

private struct HotKeySettingsRow: View {
    let action: SniprHotKeyAction
    let binding: HotKeyBinding
    let registrationFailure: OSStatus?
    let isRecording: Bool
    let conflictMessage: String?
    let onEnabledChanged: (Bool) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onRecord: (HotKeyBinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .foregroundStyle(action.isAvailable ? .primary : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)

                    Text(action.isAvailable ? action.subtitle : "Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { binding.isEnabled && action.isAvailable },
                    set: { isEnabled in
                        onEnabledChanged(isEnabled)
                    }
                ))
                .labelsHidden()
                .disabled(!action.isAvailable)

                HotKeyRecorderButton(
                    binding: binding,
                    isRecording: isRecording,
                    isEnabled: action.isAvailable && binding.isEnabled,
                    onStartRecording: onStartRecording,
                    onStopRecording: onStopRecording,
                    onRecord: onRecord
                )
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 34)
            } else if let registrationFailure {
                Text("Unavailable in macOS right now. Status \(registrationFailure).")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 3)
    }
}
