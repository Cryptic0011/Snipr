import SwiftUI

/// Sheet presenting persisted OCR results. Selecting a row re-copies the
/// recognized text to the clipboard via the coordinator and dismisses the
/// sheet. Reachable from the command palette ("Show OCR History").
struct OCRHistoryView: View {
    let coordinator: WindowCoordinator
    let history: OCRHistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OCR History")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    history.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Remove all OCR history")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No OCR Results Yet",
                    systemImage: "textformat.123",
                    description: Text("Run an OCR capture (⌘⇧O) and recognized text lands here.")
                )
                .frame(width: 460, height: 300)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(history.entries) { entry in
                            Button {
                                coordinator.recopyOCREntry(entry)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.preview)
                                            .font(.body)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
                .frame(width: 460, height: 360)
            }
        }
    }
}
