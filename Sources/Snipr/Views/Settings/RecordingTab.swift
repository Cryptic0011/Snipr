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
                Toggle("Show keystrokes", isOn: Binding(
                    get: { model.preferences.showKeystrokesWhileRecording },
                    set: { model.preferences.showKeystrokesWhileRecording = $0 }
                ))
                Text("Pressed keys appear near the bottom of the recorded area. Requires Input Monitoring access (System Settings → Privacy & Security).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show click ripples", isOn: Binding(
                    get: { model.preferences.showClicksWhileRecording },
                    set: { model.preferences.showClicksWhileRecording = $0 }
                ))

                Toggle("Show webcam bubble", isOn: Binding(
                    get: { model.preferences.showWebcamWhileRecording },
                    set: { model.preferences.showWebcamWhileRecording = $0 }
                ))

                LabeledContent("Bubble size") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.preferences.webcamBubbleDiameter },
                            set: { model.preferences.webcamBubbleDiameter = $0 }
                        ), in: 100...260, step: 10)
                        .frame(width: 180)
                        Text("\(Int(model.preferences.webcamBubbleDiameter)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!model.preferences.showWebcamWhileRecording)

                LabeledContent("Bubble border") {
                    Picker("Bubble border", selection: Binding(
                        get: { model.preferences.webcamBubbleBorderColor },
                        set: { model.preferences.webcamBubbleBorderColor = $0 }
                    )) {
                        ForEach(WebcamBorderColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(!model.preferences.showWebcamWhileRecording)

                Text("A draggable circular camera preview that records along with the screen. It starts inside the recorded area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
