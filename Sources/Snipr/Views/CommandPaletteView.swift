import SwiftUI

struct CommandPaletteView: View {
    @State private var query = ""
    @State private var selectedCommandID: SniprCommandID = .captureArea

    let onExecute: (SniprCommand) -> Void

    private var commands: [SniprCommand] {
        SniprCommand.filtered(by: query)
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

            if commands.isEmpty {
                ContentUnavailableView("No Commands", systemImage: "command", description: Text("Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedCommandID) {
                    ForEach(commands) { command in
                        CommandPaletteRow(command: command)
                            .tag(command.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onExecute(command)
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
