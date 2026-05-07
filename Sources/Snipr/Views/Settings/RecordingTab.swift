import SwiftUI

/// Recording tab — system audio toggle and supporting copy.
struct RecordingSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            Section("Recording") {
                Toggle("Record system audio", isOn: Binding(
                    get: { model.preferences.recordSystemAudio },
                    set: { model.preferences.recordSystemAudio = $0 }
                ))
                Text("Mixes desktop audio into the recording. Microphone capture is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
