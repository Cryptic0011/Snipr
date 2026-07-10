import SwiftUI

struct CommandPaletteView: View {
    @State private var query = ""
    @State private var selectedCommandID: SniprCommandID = .captureArea
    @State private var selectedWorkflowID: String?

    let onExecute: (SniprCommand) -> Void
    let onExecuteWorkflow: (Workflow) -> Void

    /// Workflows surfaced under their own section. Defaults to the
    /// built-ins; tests can supply their own.
    let workflows: [Workflow]

    /// The user's live hotkey bindings, so shortcut hints track rebinds.
    let hotKeyBindings: [SniprHotKeyAction: HotKeyBinding]

    init(
        workflows: [Workflow] = Workflow.builtIns,
        hotKeyBindings: [SniprHotKeyAction: HotKeyBinding] = HotKeyDefaults.bindings,
        onExecute: @escaping (SniprCommand) -> Void,
        onExecuteWorkflow: @escaping (Workflow) -> Void = { _ in }
    ) {
        self.workflows = workflows
        self.hotKeyBindings = hotKeyBindings
        self.onExecute = onExecute
        self.onExecuteWorkflow = onExecuteWorkflow
    }

    private var commands: [SniprCommand] {
        SniprCommand.filtered(by: query, bindings: hotKeyBindings)
    }

    private var filteredWorkflows: [Workflow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return workflows }
        return workflows.filter { workflow in
            "\(workflow.title) \(workflow.subtitle)".lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.brass)

                TextField("Search Snipr commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in
                        selectedCommandID = commands.first?.id ?? .captureArea
                    }
            }
            .padding(18)

            Divider()
                .overlay(Brand.brass.opacity(0.18))

            if commands.isEmpty && filteredWorkflows.isEmpty {
                ContentUnavailableView("No Commands", systemImage: "command", description: Text("Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedCommandID) {
                    if !commands.isEmpty {
                        Section {
                            ForEach(commands) { command in
                                CommandPaletteRow(command: command)
                                    .tag(command.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onExecute(command)
                                    }
                            }
                        } header: {
                            PaletteSectionHeader(title: "Commands")
                        }
                    }

                    if !filteredWorkflows.isEmpty {
                        Section {
                            ForEach(filteredWorkflows) { workflow in
                                WorkflowPaletteRow(workflow: workflow)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onExecuteWorkflow(workflow)
                                    }
                            }
                        } header: {
                            PaletteSectionHeader(title: "Workflows")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .tint(Brand.brass.opacity(0.22))
            }
        }
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.charcoal.opacity(0.97))
                .overlay(
                    LinearGradient(
                        colors: [Brand.brass.opacity(0.10), .clear, Brand.brassDeep.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Brand.brass.opacity(0.45), Brand.brass.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
        .frame(width: 680, height: 420)
        .onSubmit {
            if let command = commands.first(where: { $0.id == selectedCommandID }) ?? commands.first {
                onExecute(command)
            }
        }
    }
}

private struct PaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(Brand.brass.opacity(0.65))
    }
}

private struct WorkflowPaletteRow: View {
    let workflow: Workflow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill.badge.plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Brand.brass)
                .frame(width: 30, height: 30)
                .background(Brand.brassDeep.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.brass.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(workflow.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(workflow.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            Text("Workflow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.brass.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Brand.brass.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.brass.opacity(0.16)))
        }
        .padding(.vertical, 8)
    }
}

private struct CommandPaletteRow: View {
    let command: SniprCommand

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Brand.brass)
                .frame(width: 30, height: 30)
                .background(Brand.brass.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.brass.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(command.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            Text(command.shortcut)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Brand.brass.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Brand.brass.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.brass.opacity(0.16)))
        }
        .padding(.vertical, 8)
    }
}
