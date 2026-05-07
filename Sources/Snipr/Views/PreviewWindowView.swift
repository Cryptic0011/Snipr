import SwiftUI

struct PreviewWindowView: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    @State private var selectedTool: AnnotationKind = .arrow
    @State private var selectedInk: AnnotationInk = .red
    @State private var lineWidth: CGFloat = 5
    @State private var annotations: [AnnotationLayer] = []
    @State private var draftAnnotation: AnnotationLayer?
    @State private var pendingTextDraft: AnnotationLayer?
    @State private var pendingTextString: String = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            GeometryReader { proxy in
                if let image = NSImage(contentsOf: item.fileURL) {
                    AnnotationCanvasView(
                        image: image,
                        containerSize: proxy.size,
                        selectedTool: selectedTool,
                        selectedInk: selectedInk,
                        lineWidth: lineWidth,
                        annotations: annotations,
                        draftAnnotation: draftAnnotation,
                        onDraftChanged: { draftAnnotation = $0 },
                        onCommit: { annotation in
                            annotations.append(annotation)
                            draftAnnotation = nil
                        },
                        onCancelDraft: {
                            draftAnnotation = nil
                        }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(Color.black.opacity(0.88))
                } else {
                    ContentUnavailableView("Image Missing", systemImage: "photo.badge.exclamationmark")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            footer
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(item.filename)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: 190, alignment: .leading)

            Divider()
                .frame(height: 22)

            Picker("Tool", selection: $selectedTool) {
                ForEach(AnnotationKind.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 460)

            HStack(spacing: 6) {
                ForEach(AnnotationInk.allCases) { ink in
                    Button {
                        selectedInk = ink
                    } label: {
                        Circle()
                            .fill(ink.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(selectedInk == ink ? 0.95 : 0.22), lineWidth: selectedInk == ink ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(ink.rawValue.capitalized)
                }
            }

            Slider(value: $lineWidth, in: 2...12, step: 1)
                .frame(width: 82)
                .help("Line width")

            Spacer()

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(annotations.isEmpty)
            .help("Undo")

            Button {
                annotations.removeAll()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(annotations.isEmpty)
            .help("Clear annotations")

            Button {
                copyAnnotatedImage()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy annotated image")

            Button {
                saveAnnotatedImage()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save annotated image")

            Menu {
                Button("Reveal Original") {
                    coordinator.reveal(item)
                }

                Button("Copy Original") {
                    coordinator.copy(item)
                }

                Button(role: .destructive) {
                    coordinator.delete(item)
                } label: {
                    Text("Delete Original")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(12)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            Text(annotationStatus)
            Spacer()
            Text(item.dimensionsText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
    }

    private var annotationStatus: String {
        if annotations.isEmpty {
            "Draw arrows, circles, boxes, and blur regions"
        } else {
            "\(annotations.count) annotation\(annotations.count == 1 ? "" : "s")"
        }
    }

    private func undo() {
        _ = annotations.popLast()
    }

    private func copyAnnotatedImage() {
        guard let image = AnnotationRenderer.renderImage(baseURL: item.fileURL, annotations: annotations) else {
            return
        }

        ImageTransfer.copyImage(image)
    }

    private func saveAnnotatedImage() {
        guard let data = AnnotationRenderer.pngData(baseURL: item.fileURL, annotations: annotations) else {
            return
        }

        let suggestedName = item.fileURL.deletingPathExtension().lastPathComponent + "-annotated.png"
        ImageTransfer.savePNGData(data, suggestedFilename: suggestedName)
    }
}

private struct AnnotationCanvasView: View {
    let image: NSImage
    let containerSize: CGSize
    let selectedTool: AnnotationKind
    let selectedInk: AnnotationInk
    let lineWidth: CGFloat
    let annotations: [AnnotationLayer]
    let draftAnnotation: AnnotationLayer?
    let onDraftChanged: (AnnotationLayer?) -> Void
    let onCommit: (AnnotationLayer) -> Void
    let onCancelDraft: () -> Void

    var body: some View {
        let imageSize = imagePixelSize
        let displayRect = ImagePresentationGeometry.aspectFitRect(
            imageSize: imageSize,
            containerSize: containerSize
        )

        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: containerSize.width, height: containerSize.height)

            ForEach(annotations.filter { $0.kind == .blur }) { annotation in
                BlurPreviewLayer(
                    image: image,
                    containerSize: containerSize,
                    imageSize: imageSize,
                    displayRect: displayRect,
                    annotation: annotation
                )
            }

            if let draftAnnotation, draftAnnotation.kind == .blur {
                BlurPreviewLayer(
                    image: image,
                    containerSize: containerSize,
                    imageSize: imageSize,
                    displayRect: displayRect,
                    annotation: draftAnnotation
                )
            }

            Canvas { context, _ in
                for annotation in annotations {
                    draw(annotation, in: &context, imageSize: imageSize, displayRect: displayRect, isDraft: false)
                }

                if let draftAnnotation {
                    draw(draftAnnotation, in: &context, imageSize: imageSize, displayRect: displayRect, isDraft: true)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .contentShape(Rectangle())
            .gesture(drawingGesture(imageSize: imageSize, displayRect: displayRect))
        }
    }

    private var imagePixelSize: CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        return image.size
    }

    private func drawingGesture(imageSize: CGSize, displayRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let start = ImagePresentationGeometry.imagePoint(
                    from: value.startLocation,
                    imageSize: imageSize,
                    displayRect: displayRect
                ), let end = ImagePresentationGeometry.imagePoint(
                    from: value.location,
                    imageSize: imageSize,
                    displayRect: displayRect
                ) else {
                    onCancelDraft()
                    return
                }

                let ink: AnnotationInk
                switch selectedTool {
                case .blur, .pixelate, .crop:
                    ink = .white
                default:
                    ink = selectedInk
                }
                onDraftChanged(
                    AnnotationLayer(
                        kind: selectedTool,
                        start: start,
                        end: end,
                        ink: ink,
                        lineWidth: lineWidth
                    )
                )
            }
            .onEnded { _ in
                guard let draftAnnotation, draftAnnotation.isMeaningful else {
                    onCancelDraft()
                    return
                }

                onCommit(draftAnnotation)
            }
    }

    private func draw(
        _ annotation: AnnotationLayer,
        in context: inout GraphicsContext,
        imageSize: CGSize,
        displayRect: CGRect,
        isDraft: Bool
    ) {
        let start = ImagePresentationGeometry.viewPoint(
            from: annotation.start,
            imageSize: imageSize,
            displayRect: displayRect
        )
        let end = ImagePresentationGeometry.viewPoint(
            from: annotation.end,
            imageSize: imageSize,
            displayRect: displayRect
        )
        let bounds = ImagePresentationGeometry.viewRect(
            from: annotation.bounds,
            imageSize: imageSize,
            displayRect: displayRect
        )
        let opacity = isDraft ? 0.74 : 1.0
        let stroke = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)

        switch annotation.kind {
        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.ink.color.opacity(opacity)), style: stroke)
            drawArrowHead(from: start, to: end, color: annotation.ink.color.opacity(opacity), lineWidth: annotation.lineWidth, in: &context)
        case .rectangle:
            context.stroke(Path(bounds), with: .color(annotation.ink.color.opacity(opacity)), style: stroke)
        case .ellipse:
            context.stroke(Path(ellipseIn: bounds), with: .color(annotation.ink.color.opacity(opacity)), style: stroke)
        case .blur, .pixelate:
            let fill = Color.white.opacity(isDraft ? 0.04 : 0.06)
            context.fill(Path(roundedRect: bounds, cornerRadius: 8), with: .color(fill))
            context.stroke(Path(roundedRect: bounds, cornerRadius: 8), with: .color(.white.opacity(0.56)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        case .highlight:
            context.fill(Path(bounds), with: .color(annotation.ink.color.opacity(0.40)))
        case .crop:
            context.stroke(Path(bounds), with: .color(.yellow.opacity(opacity)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        case .text:
            if !annotation.text.isEmpty {
                let resolved = context.resolve(Text(annotation.text)
                    .font(.system(size: annotation.fontSize, weight: .semibold))
                    .foregroundColor(annotation.ink.color.opacity(opacity)))
                context.draw(resolved, at: start, anchor: .bottomLeading)
            } else if isDraft {
                context.stroke(Path(roundedRect: CGRect(x: start.x, y: start.y - annotation.fontSize, width: 80, height: annotation.fontSize), cornerRadius: 4), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        case .step:
            let radius = max(14, annotation.lineWidth * 3)
            let circle = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(annotation.ink.color.opacity(opacity)))
            context.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
            let label = Text("\(annotation.stepNumber)")
                .font(.system(size: radius, weight: .bold))
                .foregroundColor(.white)
            let resolved = context.resolve(label)
            context.draw(resolved, at: start, anchor: .center)
        }
    }

    private func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 20
        let spread: CGFloat = .pi / 7
        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )

        var path = Path()
        path.move(to: first)
        path.addLine(to: end)
        path.addLine(to: second)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

private struct BlurPreviewLayer: View {
    let image: NSImage
    let containerSize: CGSize
    let imageSize: CGSize
    let displayRect: CGRect
    let annotation: AnnotationLayer

    var body: some View {
        let rect = ImagePresentationGeometry.viewRect(
            from: annotation.bounds,
            imageSize: imageSize,
            displayRect: displayRect
        )

        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: containerSize.width, height: containerSize.height)
            .blur(radius: 12)
            .mask {
                Rectangle()
                    .fill(.white)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
            }
            .allowsHitTesting(false)
    }
}
