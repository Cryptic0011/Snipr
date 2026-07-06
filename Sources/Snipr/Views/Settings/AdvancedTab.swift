import SwiftUI

/// Advanced tab — diagnostic and power-user knobs. Currently houses the
/// "no built-in cloud upload" reminder and the local-first guarantees so
/// users have one place to confirm Snipr's privacy model.
struct AdvancedSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
            Section("Privacy") {
                Label("Snipr is local-first.", systemImage: "lock.shield")
                    .font(.headline)
                Text("Captures, recordings, OCR results, and pinned references stay on this Mac. There is no telemetry, no account, and no built-in cloud upload — sharing routes through the system Share menu only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Workflows") {
                Text("Built-in chained workflows live in the command palette under their own section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Workflow.builtIns) { workflow in
                    LabeledContent(workflow.title) {
                        Text(workflow.steps.map(\.title).joined(separator: " → "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
