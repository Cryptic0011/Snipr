import SwiftUI

/// Annotation tab — tool catalog and color sampler output preferences.
struct AnnotationSettingsTab: View {
    let model: SniprAppModel

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
