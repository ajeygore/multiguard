import SwiftUI

/// Edit a profile's name and its WireGuard config in place, instead of deleting and re-importing it.
struct ProfileEditorView: View {
    let tunnel: Tunnel
    @ObservedObject var viewModel: TunnelListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var content = ""
    @State private var originalContent = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                Text("Edit Profile")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(validationError == nil ? Color.secondary.opacity(0.25) : Theme.error.opacity(0.6), lineWidth: 1)
                )
                .disabled(loadError != nil)

            if let message = loadError ?? validationError ?? saveError {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.error)
            } else if isConnected && hasConfigChanges {
                Label("The tunnel will be disconnected and reconnected with the new config.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isConnected && hasConfigChanges ? "Save & Reconnect" : "Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
        .task {
            name = tunnel.name
            do {
                content = try await viewModel.configContent(for: tunnel)
                originalContent = content
            } catch {
                loadError = "Could not read the config file: \(error.localizedDescription)"
            }
        }
    }

    private var isConnected: Bool {
        viewModel.tunnels.first(where: { $0.id == tunnel.id })?.status.isConnected ?? false
    }

    private var hasConfigChanges: Bool {
        content != originalContent
    }

    /// Parse on every keystroke so a broken config is flagged before Save.
    private var validationError: String? {
        guard loadError == nil, !content.isEmpty else { return nil }
        do {
            _ = try ConfigParser.parse(content)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canSave: Bool {
        loadError == nil && validationError == nil && !isSaving
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasConfigChanges || name != tunnel.name)
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                // Only a changed config needs the reconnect; a rename alone just saves.
                if hasConfigChanges {
                    try await viewModel.updateProfile(tunnel, name: name, content: content)
                } else {
                    viewModel.rename(tunnel, to: name)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
