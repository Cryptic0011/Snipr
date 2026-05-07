import SwiftUI

/// General settings tab — permissions and stack behavior. Phase 4 splits the
/// monolithic Settings form into one view per topic; behavior is unchanged
/// (the `model` reference and `Section`s are copy/moved verbatim).
struct GeneralSettingsTab: View {
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
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
