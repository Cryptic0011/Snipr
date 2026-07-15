import AppKit
import SwiftUI

/// Shared "Style" popover for share-ready exports: backdrop preset, solid
/// color, custom image, frame sliders, and canvas aspect. Used by both the
/// video trim pane and the screenshot annotation editor — bind each surface's
/// own persisted `backdrop`/`style`.
struct ExportStylePopover: View {
    @Binding var backdrop: VideoBackdrop?
    @Binding var style: ExportStyle

    private var customImageName: String? {
        if case .customImage(let url) = backdrop { return url.lastPathComponent }
        return nil
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                if case .color(let rgba) = backdrop { return rgba.color }
                return Color.black
            },
            set: { backdrop = .color(RGBA(color: $0)) }
        )
    }

    var body: some View {
        Form {
            Section("Background") {
                Picker("Preset", selection: $backdrop) {
                    Text("None").tag(VideoBackdrop?.none)
                    // .color and .customImage are chosen via the ColorPicker
                    // and file chooser below, not this list — without a
                    // matching tag for them, selecting either produces a
                    // SwiftUI "no tag matching selection" runtime warning.
                    switch backdrop {
                    case .color, .customImage:
                        Text(backdrop?.title ?? "").tag(backdrop).disabled(true)
                    default:
                        EmptyView()
                    }
                    ForEach(VideoBackdrop.pickerGroups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.options) { option in
                                Text(option.title).tag(VideoBackdrop?.some(option))
                            }
                        }
                    }
                }

                SwiftUI.ColorPicker("Color", selection: colorBinding, supportsOpacity: false)

                LabeledContent("Custom Image") {
                    Button(customImageName ?? "Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            backdrop = .customImage(url)
                        }
                    }
                }

                if case .bundled = backdrop {
                    Text("Bundled wallpapers courtesy of the Recordly project.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Frame") {
                LabeledContent("Padding") {
                    Slider(value: $style.paddingFraction, in: 0...0.30)
                    Text(style.paddingFraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Corner radius") {
                    Slider(value: $style.cornerRadius, in: 0...40)
                    Text("\(Int(style.cornerRadius))")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Shadow") {
                    Slider(value: $style.shadowOpacity, in: 0...1)
                    Text(style.shadowOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }

            Section("Canvas") {
                Picker("Aspect", selection: $style.aspect) {
                    ForEach(CanvasAspect.allCases) { aspect in
                        Text(aspect.title).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding(8)
    }
}

/// Editor-pane approximation of an export backdrop.
struct BackdropPreview: View {
    let backdrop: VideoBackdrop

    var body: some View {
        switch backdrop {
        case .gradient(let style):
            style.previewGradient
        case .bundled, .wallpaper, .customImage:
            if let image = backdrop.resolveImage(for: nil) {
                Image(nsImage: image).resizable().scaledToFill().clipped()
            } else {
                BeautifyStyle.graphite.previewGradient
            }
        case .color(let rgba):
            rgba.color
        }
    }
}
