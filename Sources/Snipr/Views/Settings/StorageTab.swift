import SwiftUI

/// Storage tab — surface the on-disk capture root.
struct StorageSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Capture Folder") {
                    Text(model.captureStore.rootDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.captureStore.rootDirectory])
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
