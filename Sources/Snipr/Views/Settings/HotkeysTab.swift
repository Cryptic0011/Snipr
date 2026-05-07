import SwiftUI

/// Hotkeys tab — relocates `HotKeysSettingsSection` (and the row/recorder
/// support views previously file-private to `SniprApp.swift`) so the Phase 4
/// settings TabView can compose them. Behavior is unchanged from Phase 3.
struct HotkeysSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            HotKeysSettingsSection(model: model)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

struct HotKeysSettingsSection: View {
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

struct HotKeySettingsRow: View {
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
