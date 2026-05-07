import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating thumbnail stack panel.
///
/// Two visual states share one panel:
/// 1. **Pile** — overlapping cards, 3–5 px offset and 0.5–1.5° tilt per
///    item, capped at 6 visible cards. Mimics a physical pile of photos.
/// 2. **Expanded sidebar** — Raycast-style vertical list with a thin
///    border, ultra-thin material blur, per-card quick actions, and a
///    batch-action menu in the header.
///
/// Hover transitions between the two; the presenter animates the panel
/// frame so the SwiftUI view only worries about the hovered/expanded
/// state of its content.
struct ThumbnailStackView: View {
    let store: CaptureStore
    let coordinator: WindowCoordinator

    @State private var selection: Set<UUID> = []
    @State private var lastClickedID: UUID?
    @State private var focusedID: UUID?
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        Group {
            if coordinator.isThumbnailStackExpanded {
                ExpandedSidebar(
                    store: store,
                    coordinator: coordinator,
                    selection: $selection,
                    lastClickedID: $lastClickedID,
                    focusedID: $focusedID,
                    keyboardFocused: $keyboardFocused
                )
            } else {
                CollapsedPile(store: store, coordinator: coordinator)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: coordinator.isThumbnailStackExpanded)
        .onHover { hovered in
            coordinator.setThumbnailStackHovering(hovered)
        }
        .onChange(of: coordinator.isThumbnailStackExpanded) { _, expanded in
            keyboardFocused = expanded
            if expanded, focusedID == nil {
                focusedID = store.items.first?.id
            }
        }
    }
}

// MARK: - Collapsed pile

private struct CollapsedPile: View {
    let store: CaptureStore
    let coordinator: WindowCoordinator
    private let layout = ThumbnailPileLayout.default

    var body: some View {
        let total = store.items.count
        let visible = ThumbnailPileLayout.visibleCardCount(forTotal: total)
        let visibleItems = Array(store.items.prefix(visible))

        ZStack(alignment: .topTrailing) {
            // Background blur so the pile reads as a single object.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                )

            ZStack {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { pair in
                    let placement = layout.placement(forIndex: pair.offset, totalCount: total)
                    PileCard(item: pair.element, coordinator: coordinator)
                        .scaleEffect(placement.scale)
                        .rotationEffect(.degrees(placement.rotationDegrees))
                        .offset(x: placement.xOffset, y: placement.yOffset)
                        .opacity(placement.opacity)
                        .zIndex(placement.zIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                Text("\(total)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                Text("Stack")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(10)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PileCard: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator

    var body: some View {
        MediaThumbnailView(
            item: item,
            size: CGSize(width: 188, height: 110),
            cornerRadius: 6
        )
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

// MARK: - Expanded sidebar

private struct ExpandedSidebar: View {
    let store: CaptureStore
    let coordinator: WindowCoordinator
    @Binding var selection: Set<UUID>
    @Binding var lastClickedID: UUID?
    @Binding var focusedID: UUID?
    var keyboardFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.items) { item in
                            SidebarRow(
                                item: item,
                                coordinator: coordinator,
                                isSelected: selection.contains(item.id),
                                isFocused: focusedID == item.id,
                                dragURLs: { dragURLs(triggeredBy: item) },
                                onTap: { event in handleTap(item: item, event: event) },
                                onPin: { coordinator.pin(item) }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: focusedID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .focusable()
        .focused(keyboardFocused)
        .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
        .onKeyPress(.return) { activateFocused(); return .handled }
        .onKeyPress(.delete) { deleteFocused(); return .handled }
        .onKeyPress(.deleteForward) { deleteFocused(); return .handled }
        .onKeyPress(keys: ["c"]) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            copyFocused(); return .handled
        }
        .onKeyPress(keys: ["p"]) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            pinFocused(); return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Snipr Stack")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))

            Text("\(store.items.count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.10), in: Capsule())

            Spacer()

            Menu {
                Button("Save All to Folder…") { saveAllToFolder() }
                    .disabled(activeImageItems().isEmpty && activeItems().isEmpty)
                Button("Combine into PDF…") { combineIntoPDF() }
                    .disabled(activeImageItems().isEmpty)
                Button("Stitch Vertically…") { stitchVertically() }
                    .disabled(activeImageItems().isEmpty)
                Divider()
                Button("Clear Stack", role: .destructive) {
                    coordinator.clearStack()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption.weight(.bold))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 22)
            .help("Batch actions")

            Button {
                coordinator.setThumbnailStackPinned(!coordinator.isThumbnailStackPinned)
            } label: {
                Image(systemName: coordinator.isThumbnailStackPinned ? "pin.fill" : "pin")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(StackIconButtonStyle(isActive: coordinator.isThumbnailStackPinned))
            .help(coordinator.isThumbnailStackPinned ? "Unpin stack" : "Pin stack")

            Button {
                coordinator.hideThumbnailStack()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(StackIconButtonStyle(isActive: false))
            .help("Hide stack")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    // MARK: Selection / keyboard

    private func handleTap(item: CaptureItem, event: NSEvent.ModifierFlags) {
        if event.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else if event.contains(.shift), let anchor = lastClickedID,
                  let anchorIndex = store.items.firstIndex(where: { $0.id == anchor }),
                  let tapIndex = store.items.firstIndex(where: { $0.id == item.id }) {
            let lower = min(anchorIndex, tapIndex)
            let upper = max(anchorIndex, tapIndex)
            let range = store.items[lower...upper].map(\.id)
            for id in range {
                selection.insert(id)
            }
        } else {
            selection = [item.id]
        }
        lastClickedID = item.id
        focusedID = item.id
    }

    private func moveFocus(by delta: Int) {
        guard !store.items.isEmpty else { return }
        let currentIndex = focusedID.flatMap { id in store.items.firstIndex(where: { $0.id == id }) } ?? -1
        let next = max(0, min(store.items.count - 1, currentIndex + delta))
        focusedID = store.items[next].id
    }

    private func activateFocused() {
        guard let id = focusedID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        coordinator.openPreview(for: item)
    }

    private func copyFocused() {
        for item in activeItems() {
            coordinator.copy(item)
        }
    }

    private func deleteFocused() {
        let targets = activeItems()
        for item in targets {
            coordinator.delete(item)
        }
        if let id = focusedID, store.items.contains(where: { $0.id == id }) == false {
            focusedID = store.items.first?.id
        }
        selection.removeAll()
    }

    private func pinFocused() {
        guard let id = focusedID,
              let item = store.items.first(where: { $0.id == id }),
              item.mediaType == .image else { return }
        coordinator.pin(item)
    }

    /// Items the keyboard / batch action should target — selection if any,
    /// else the currently focused row, else the entire visible stack.
    private func activeItems() -> [CaptureItem] {
        if !selection.isEmpty {
            return store.items.filter { selection.contains($0.id) }
        }
        if let id = focusedID,
           let item = store.items.first(where: { $0.id == id }) {
            return [item]
        }
        return store.items
    }

    private func activeImageItems() -> [CaptureItem] {
        activeItems().filter { $0.mediaType == .image }
    }

    /// URLs dragged out when the user begins a drag from `item`.
    ///
    /// Per the Phase 2 brief: drag carries the selection if any, else all
    /// visible items so the user can fling the entire stack into Discord
    /// without first multi-selecting. If a drag fires on a row outside the
    /// current selection, that one row wins.
    private func dragURLs(triggeredBy item: CaptureItem) -> [URL] {
        if !selection.isEmpty {
            if selection.contains(item.id) {
                // Preserve the displayed order so dropped files land in
                // the same sequence the user sees.
                return store.items.filter { selection.contains($0.id) }.map(\.fileURL)
            }
            return [item.fileURL]
        }
        return store.items.map(\.fileURL)
    }

    // MARK: Batch actions

    private func saveAllToFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.title = "Save Stack to Folder"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let items = activeItems().isEmpty ? store.items : activeItems()
        for item in items {
            let destination = directory.appending(path: item.filename)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: item.fileURL, to: destination)
            } catch {
                NSAlert(error: error).runModal()
                return
            }
        }
    }

    private func combineIntoPDF() {
        let images = activeImageItems().isEmpty
            ? store.items.filter { $0.mediaType == .image }
            : activeImageItems()
        guard !images.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Snipr Stack.pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            // Order in the PDF is the order shown in the sidebar — most
            // recent first matches what the user is looking at.
            try PDFCombiner.combine(imageURLs: images.map(\.fileURL), to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func stitchVertically() {
        let images = activeImageItems().isEmpty
            ? store.items.filter { $0.mediaType == .image }
            : activeImageItems()
        guard !images.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snipr Stitched.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try VerticalStitcher.stitchVertically(imageURLs: images.map(\.fileURL), to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct SidebarRow: View {
    let item: CaptureItem
    let coordinator: WindowCoordinator
    let isSelected: Bool
    let isFocused: Bool
    let dragURLs: () -> [URL]
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onPin: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MediaThumbnailView(
                item: item,
                size: CGSize(width: 92, height: 60),
                cornerRadius: 4
            )
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.95))

                Text(item.detailText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))

                if isHovering {
                    quickActions
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dedicated drag handle. Living here keeps SwiftUI tap
            // gestures owning the thumbnail/labels (single/double click
            // still select and open the preview), while the user has a
            // visible grip to fling the selection out into Finder, Slack,
            // or Discord.
            ZStack {
                Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 36)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                MultiFileDragView(urlsProvider: dragURLs)
                    .frame(width: 22, height: 36)
            }
            .help("Drag to copy out — multi-select to drag many")
        }
        .padding(8)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: isSelected ? 2 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isFocused && !isSelected ? Color.white.opacity(0.45) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                coordinator.openPreview(for: item)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                onTap(NSApp.currentEvent?.modifierFlags ?? [])
            }
        )
        .contextMenu {
            CaptureContextMenu(item: item, coordinator: coordinator)
        }
    }

    private var rowBackground: some View {
        let base = Color.white.opacity(isSelected ? 0.12 : (isHovering ? 0.08 : 0.04))
        return RoundedRectangle(cornerRadius: 6, style: .continuous).fill(base)
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            QuickActionButton(systemImage: "doc.on.doc", help: "Copy") {
                coordinator.copy(item)
            }
            QuickActionButton(systemImage: "square.and.arrow.down", help: "Save As…") {
                coordinator.saveAs(item)
            }
            QuickActionButton(systemImage: "folder", help: "Reveal in Finder") {
                coordinator.reveal(item)
            }
            QuickActionButton(systemImage: "pin", help: "Pin to floating window") {
                onPin()
            }
            QuickActionButton(systemImage: "pencil.tip.crop.circle", help: "Annotate") {
                coordinator.openPreview(for: item)
            }
            QuickActionButton(systemImage: "trash", help: "Delete") {
                coordinator.delete(item)
            }
        }
    }
}

private struct QuickActionButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 22, height: 18)
                .foregroundStyle(.white.opacity(0.78))
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct StackIconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : .white.opacity(0.58))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.white.opacity(0.16) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
    }
}
