import SwiftUI

/// Capture tab — clipboard / disk / format / filename template settings.
struct CaptureSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Copy to clipboard on capture", isOn: Binding(
                    get: { model.preferences.copyToClipboardOnCapture },
                    set: { model.preferences.copyToClipboardOnCapture = $0 }
                ))

                Toggle("Save to disk", isOn: Binding(
                    get: { model.preferences.saveToDiskOnCapture },
                    set: { model.preferences.saveToDiskOnCapture = $0 }
                ))

                Toggle("Show magnifier while selecting", isOn: Binding(
                    get: { model.preferences.showCaptureMagnifier },
                    set: { model.preferences.showCaptureMagnifier = $0 }
                ))

                Toggle("Freeze screen while selecting", isOn: Binding(
                    get: { model.preferences.freezeScreenDuringSelection },
                    set: { model.preferences.freezeScreenDuringSelection = $0 }
                ))

                LabeledContent("Self-timer") {
                    Picker("Self-timer", selection: Binding(
                        get: { model.preferences.captureDelaySeconds },
                        set: { model.preferences.captureDelaySeconds = $0 }
                    )) {
                        Text("Off").tag(0)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

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

            Section("Smart Folders") {
                SmartFolderRulesEditor(model: model)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

/// Inline editor for the Phase 4 smart-folder routing rules. Kept small —
/// add row, edit pattern + subfolder, remove. Live preference binding so
/// edits flush to UserDefaults without a Save button.
private struct SmartFolderRulesEditor: View {
    let model: SniprAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.preferences.smartFolderRules) { rule in
                HStack(spacing: 8) {
                    TextField("App contains", text: Binding(
                        get: { rule.appPattern },
                        set: { newValue in updateRule(id: rule.id) { $0.appPattern = newValue } }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("Subfolder", text: Binding(
                        get: { rule.subfolder },
                        set: { newValue in updateRule(id: rule.id) { $0.subfolder = newValue } }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        removeRule(id: rule.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove rule")
                }
            }

            Button {
                addRule()
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            Text("First match wins. Empty patterns match nothing — captures fall back to the default folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addRule() {
        var rules = model.preferences.smartFolderRules
        rules.append(SmartFolderRule(appPattern: "", subfolder: ""))
        model.preferences.smartFolderRules = rules
    }

    private func removeRule(id: UUID) {
        model.preferences.smartFolderRules.removeAll { $0.id == id }
    }

    private func updateRule(id: UUID, mutate: (inout SmartFolderRule) -> Void) {
        var rules = model.preferences.smartFolderRules
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rules[index])
        model.preferences.smartFolderRules = rules
    }
}
