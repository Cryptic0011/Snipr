import SwiftUI

/// Recording tab — container format, audio sources, and the on-screen
/// companions (input overlays, webcam bubble).
struct RecordingSettingsTab: View {
    let model: SniprAppModel

    private var supportsMicCapture: Bool {
        if #available(macOS 15.0, *) { true } else { false }
    }

    var body: some View {
        Form {
            Section("Recording") {
                LabeledContent("Format") {
                    Picker("Format", selection: Binding(
                        get: { model.preferences.recordingFormat },
                        set: { model.preferences.recordingFormat = $0 }
                    )) {
                        ForEach(RecordingFileFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }

                Toggle("Record system audio", isOn: Binding(
                    get: { model.preferences.recordSystemAudio },
                    set: { model.preferences.recordSystemAudio = $0 }
                ))

                Toggle("Record microphone", isOn: Binding(
                    get: { model.preferences.recordMicrophone },
                    set: { model.preferences.recordMicrophone = $0 }
                ))
                .disabled(!supportsMicCapture)

                Text(supportsMicCapture
                    ? "Microphone lands on its own audio track alongside system audio."
                    : "Microphone capture requires macOS 15 or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While recording") {
                Toggle("Show keystrokes and clicks", isOn: Binding(
                    get: { model.preferences.showInputOverlaysWhileRecording },
                    set: { model.preferences.showInputOverlaysWhileRecording = $0 }
                ))
                Text("Pressed keys and click ripples appear on screen and are captured in the recording. Requires Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show webcam bubble", isOn: Binding(
                    get: { model.preferences.showWebcamWhileRecording },
                    set: { model.preferences.showWebcamWhileRecording = $0 }
                ))
                Text("A draggable circular camera preview that records along with the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
