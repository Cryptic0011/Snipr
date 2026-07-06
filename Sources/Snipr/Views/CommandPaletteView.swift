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
                    .foregroundStyle(.secondary)

                TextField("Search Snipr commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in
                        selectedCommandID = commands.first?.id ?? .captureArea
                    }
            }
            .padding(18)

            Divider()
                .overlay(Color.white.opacity(0.08))

            if commands.isEmpty && filteredWorkflows.isEmpty {
                ContentUnavailableView("No Commands", systemImage: "command", description: Text("Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedCommandID) {
                    if !commands.isEmpty {
                        Section("Commands") {
                            ForEach(commands) { command in
                                CommandPaletteRow(command: command)
                                    .tag(command.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onExecute(command)
                                    }
                            }
                        }
                    }

                    if !filteredWorkflows.isEmpty {
                        Section("Workflows") {
                            ForEach(filteredWorkflows) { workflow in
                                WorkflowPaletteRow(workflow: workflow)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onExecuteWorkflow(workflow)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(width: 680, height: 420)
        .onSubmit {
            if let command = commands.first(where: { $0.id == selectedCommandID }) ?? commands.first {
                onExecute(command)
            }
        }
    }
}

private struct WorkflowPaletteRow: View {
    let workflow: Workflow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill.badge.plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.purple)
                .frame(width: 24)

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
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 8)
    }
}

private struct CommandPaletteRow: View {
    let command: SniprCommand

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.cyan)
                .frame(width: 24)

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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 8)
    }
}
