import CoreImage
import CoreImage.CIFilterBuiltins
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
    /// Existing text annotation being re-edited via double-click, if any.
    @State private var editingTextID: UUID?
    @State private var selection: UUID?
    // Snapshot-based undo: every mutation pushes the whole layer array.
    // Annotation stacks are tiny, so this stays cheap and makes add, move,
    // delete, edit, and clear all undoable through one mechanism.
    @State private var undoStack: [[AnnotationLayer]] = []
    @State private var redoStack: [[AnnotationLayer]] = []

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
                        selectedID: selection,
                        onDraftChanged: { draftAnnotation = $0 },
                        onCommit: { annotation in
                            commit(annotation)
                        },
                        onCancelDraft: {
                            draftAnnotation = nil
                        },
                        onSelect: { selection = $0 },
                        onMoveBegan: { pushUndo() },
                        onUpdate: { updated in
                            if let index = annotations.firstIndex(where: { $0.id == updated.id }) {
                                annotations[index] = updated
                            }
                        },
                        onEditText: { id in
                            guard let existing = annotations.first(where: { $0.id == id }) else { return }
                            editingTextID = id
                            pendingTextString = existing.text
                            pendingTextDraft = existing
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
        .sheet(isPresented: Binding(
            get: { pendingTextDraft != nil },
            set: { if !$0 { pendingTextDraft = nil } }
        )) {
            VStack(alignment: .leading, spacing: 14) {
                Text(editingTextID == nil ? "Add Text Annotation" : "Edit Text Annotation")
                    .font(.headline)
                TextField("Text", text: $pendingTextString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        pendingTextDraft = nil
                        pendingTextString = ""
                        editingTextID = nil
                    }
                    Button(editingTextID == nil ? "Add" : "Save") {
                        if let editingTextID,
                           let index = annotations.firstIndex(where: { $0.id == editingTextID }) {
                            if !pendingTextString.isEmpty, annotations[index].text != pendingTextString {
                                pushUndo()
                                annotations[index].text = pendingTextString
                            }
                        } else if var draft = pendingTextDraft {
                            draft.text = pendingTextString
                            if !draft.text.isEmpty {
                                pushUndo()
                                annotations.append(draft)
                            }
                        }
                        pendingTextDraft = nil
                        pendingTextString = ""
                        editingTextID = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            // No filename here — the window title bar already shows it, and a
            // second truncated copy just crowded the tool row.
            Picker("Tool", selection: $selectedTool) {
                ForEach(AnnotationKind.editorTools) { tool in
                    Image(systemName: tool.systemImage)
                        .help(tool.title)
                        .accessibilityLabel(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Annotation tool: \(selectedTool.title)")

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
                    .accessibilityLabel("\(ink.rawValue.capitalized) ink")
                    .accessibilityAddTraits(selectedInk == ink ? .isSelected : [])
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
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(undoStack.isEmpty)
            .help("Undo (⌘Z)")
            .accessibilityLabel("Undo")

            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(redoStack.isEmpty)
            .help("Redo (⇧⌘Z)")
            .accessibilityLabel("Redo")

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(selection == nil)
            .help("Delete selected annotation (⌫)")
            .accessibilityLabel("Delete selected annotation")

            Button {
                pushUndo()
                annotations.removeAll()
                selection = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(annotations.isEmpty)
            .help("Clear annotations")
            .accessibilityLabel("Clear annotations")

            Button {
                copyAnnotatedImage()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command])
            .help("Copy annotated image")
            .accessibilityLabel("Copy annotated image")

            Button {
                saveAnnotatedImage()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save annotated image")
            .accessibilityLabel("Save annotated image")

            // Phase 4 quick share: NSSharingServicePicker anchored on this
            // toolbar. Shares the original file URL — annotation export still
            // lives behind the explicit "Save annotated image" action above.
            ShareButton(symbolName: "square.and.arrow.up", helpText: "Share") { [item] in
                [item.fileURL]
            }
            .frame(width: 22, height: 22)

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
            .accessibilityLabel("More actions")
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

    private func commit(_ annotation: AnnotationLayer) {
        var draft = annotation
        switch annotation.kind {
        case .step:
            // Auto-increment based on existing step counters in the layer stack.
            let nextNumber = (annotations.filter { $0.kind == .step }.map(\.stepNumber).max() ?? 0) + 1
            draft.stepNumber = nextNumber
            pushUndo()
            annotations.append(draft)
            draftAnnotation = nil
        case .text:
            // Defer commit until the user types text in the popover; the
            // sheet's Add button pushes the undo snapshot.
            editingTextID = nil
            pendingTextDraft = draft
            pendingTextString = ""
            draftAnnotation = nil
        default:
            pushUndo()
            annotations.append(draft)
            draftAnnotation = nil
        }
    }

    private func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selection = nil
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selection = nil
    }

    private func deleteSelected() {
        guard let selection, let index = annotations.firstIndex(where: { $0.id == selection }) else { return }
        pushUndo()
        annotations.remove(at: index)
        self.selection = nil
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
    let selectedID: UUID?
    let onDraftChanged: (AnnotationLayer?) -> Void
    let onCommit: (AnnotationLayer) -> Void
    let onCancelDraft: () -> Void
    let onSelect: (UUID?) -> Void
    let onMoveBegan: () -> Void
    let onUpdate: (AnnotationLayer) -> Void
    let onEditText: (UUID) -> Void

    /// Active drag-to-move of an existing annotation. Geometry is offset from
    /// the annotation's position at drag start so the move stays absolute.
    private struct MoveState {
        let id: UUID
        let originalStart: CGPoint
        let originalEnd: CGPoint
        var didPushUndo: Bool
    }

    @State private var moveState: MoveState?

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

            ForEach(annotations.filter { AnnotationEffectPreview.supportsLivePreview($0.kind) }) { annotation in
                EffectPreviewLayer(
                    image: image,
                    containerSize: containerSize,
                    imageSize: imageSize,
                    displayRect: displayRect,
                    annotation: annotation
                )
            }

            if let draftAnnotation, AnnotationEffectPreview.supportsLivePreview(draftAnnotation.kind) {
                EffectPreviewLayer(
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
            .gesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    if let point = ImagePresentationGeometry.imagePoint(
                        from: value.location, imageSize: imageSize, displayRect: displayRect
                    ), let hit = topmostAnnotation(at: point), hit.kind == .text {
                        onEditText(hit.id)
                    }
                }
            )
            .gesture(drawingGesture(imageSize: imageSize, displayRect: displayRect))
        }
    }

    /// Last-drawn annotation wins, matching the visual stacking order.
    private func topmostAnnotation(at point: CGPoint) -> AnnotationLayer? {
        annotations.reversed().first { annotation in
            AnnotationToolRegistry.tool(for: annotation.kind)?.hitTest(annotation, point: point) == true
        }
    }

    private var imagePixelSize: CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        return image.size
    }

    private func drawingGesture(imageSize: CGSize, displayRect: CGRect) -> some Gesture {
        // minimumDistance 0 for every tool: the first event decides whether
        // this drag moves an existing annotation (press landed on one) or
        // draws a new one. Sub-8px new-shape drafts are still discarded by
        // isMeaningful, so plain clicks on empty space just deselect.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scale = displayRect.width / max(imageSize.width, 1)

                if moveState == nil, draftAnnotation == nil,
                   let pressPoint = ImagePresentationGeometry.imagePoint(
                       from: value.startLocation, imageSize: imageSize, displayRect: displayRect
                   ), let hit = topmostAnnotation(at: pressPoint) {
                    moveState = MoveState(
                        id: hit.id,
                        originalStart: hit.start,
                        originalEnd: hit.end,
                        didPushUndo: false
                    )
                    onSelect(hit.id)
                }

                if var move = moveState {
                    guard var annotation = annotations.first(where: { $0.id == move.id }), scale > 0 else { return }
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    if !move.didPushUndo, hypot(dx, dy) * scale > 2 {
                        onMoveBegan()
                        move.didPushUndo = true
                        moveState = move
                    }
                    guard move.didPushUndo else { return }
                    annotation.start = CGPoint(x: move.originalStart.x + dx, y: move.originalStart.y + dy)
                    annotation.end = CGPoint(x: move.originalEnd.x + dx, y: move.originalEnd.y + dy)
                    onUpdate(annotation)
                    return
                }

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
                case .blur, .pixelate:
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
                if moveState != nil {
                    moveState = nil
                    return
                }

                guard let draftAnnotation, draftAnnotation.isMeaningful else {
                    // A click on empty space: no shape drawn, drop selection.
                    onSelect(nil)
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
        // Annotation geometry (start/end/lineWidth/fontSize) lives in image
        // pixels; the canvas paints in view points. Scale painted sizes by the
        // same factor as positions so the live preview matches the export.
        let scale = imageSize.width > 0 ? displayRect.width / imageSize.width : 1
        let stroke = StrokeStyle(lineWidth: annotation.lineWidth * scale, lineCap: .round, lineJoin: .round)

        switch annotation.kind {
        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.ink.color.opacity(opacity)), style: stroke)
            drawArrowHead(from: start, to: end, color: annotation.ink.color.opacity(opacity), lineWidth: annotation.lineWidth * scale, scale: scale, in: &context)
        case .line:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.ink.color.opacity(opacity)), style: stroke)
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
            let fontSize = annotation.fontSize * scale
            if !annotation.text.isEmpty {
                let resolved = context.resolve(Text(annotation.text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(annotation.ink.color.opacity(opacity)))
                // topLeading: the export (TextTool) and its hit test both put
                // the text below-right of the tap point.
                context.draw(resolved, at: start, anchor: .topLeading)
            } else if isDraft {
                context.stroke(Path(roundedRect: CGRect(x: start.x, y: start.y, width: 80 * scale, height: fontSize), cornerRadius: 4), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        case .step:
            // Same radius formula as StepTool so the preview matches the export.
            let radius = max(18, annotation.lineWidth * 4) * scale
            let circle = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(annotation.ink.color.opacity(opacity)))
            context.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
            let label = Text("\(annotation.stepNumber)")
                .font(.system(size: radius, weight: .bold))
                .foregroundColor(.white)
            let resolved = context.resolve(label)
            context.draw(resolved, at: start, anchor: .center)
        }

        if !isDraft, annotation.id == selectedID {
            let highlightRect: CGRect
            switch annotation.kind {
            case .text:
                let resolved = context.resolve(Text(annotation.text)
                    .font(.system(size: annotation.fontSize * scale, weight: .semibold)))
                let size = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                highlightRect = CGRect(x: start.x, y: start.y, width: size.width, height: size.height)
            case .step:
                let radius = max(18, annotation.lineWidth * 4) * scale
                highlightRect = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
            default:
                highlightRect = bounds
            }
            context.stroke(
                Path(roundedRect: highlightRect.insetBy(dx: -6, dy: -6), cornerRadius: 6),
                with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }
    }

    private func drawArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        scale: CGFloat,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        // Same head length as ArrowTool so the preview matches the export.
        let length: CGFloat = 18 * scale
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

enum AnnotationEffectPreview {
    static func supportsLivePreview(_ kind: AnnotationKind) -> Bool {
        kind == .blur || kind == .pixelate
    }
}

private struct EffectPreviewLayer: View {
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

        Image(nsImage: previewImage)
            .resizable()
            .scaledToFit()
            .frame(width: containerSize.width, height: containerSize.height)
            .modifier(PreviewEffectModifier(kind: annotation.kind))
            .mask {
                Rectangle()
                    .fill(.white)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
            }
            .allowsHitTesting(false)
    }

    private var previewImage: NSImage {
        switch annotation.kind {
        case .pixelate:
            pixelatedImage ?? image
        default:
            image
        }
    }

    private var pixelatedImage: NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage.clampedToExtent()
        filter.scale = Float(max(8, min(annotation.bounds.width, annotation.bounds.height) / 16))
        filter.center = CGPoint(x: CGFloat(cgImage.width) / 2, y: CGFloat(cgImage.height) / 2)

        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard let output = filter.outputImage?.cropped(to: extent),
              let pixelated = CIContext(options: nil).createCGImage(output, from: extent) else {
            return nil
        }

        return NSImage(cgImage: pixelated, size: CGSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct PreviewEffectModifier: ViewModifier {
    let kind: AnnotationKind

    @ViewBuilder
    func body(content: Content) -> some View {
        switch kind {
        case .blur:
            content.blur(radius: 12)
        default:
            content
        }
    }
}
