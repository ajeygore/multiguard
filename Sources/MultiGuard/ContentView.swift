import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = AppState.shared.viewModel
    @StateObject private var appearance = AppearanceController.shared
    @State private var showingImporter = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.conflicts.isEmpty {
                        conflictBanner
                    }

                    if viewModel.tunnels.isEmpty {
                        emptyState
                    } else {
                        statusSummary
                        bulkActionBar
                        tunnelsList
                    }

                    if let error = viewModel.importError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Theme.error)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(Theme.error)
                            Spacer()
                            Button {
                                copyToClipboard(error)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Copy error to clipboard")
                        }
                        .padding(12)
                        .background(Theme.error.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.windowBackground)
        .onAppear {
            AppDelegate.openWindow = openWindow
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    viewModel.importConfig(from: url)
                }
            case .failure(let error):
                viewModel.importError = error.localizedDescription
            }
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("MultiGuard")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Multi-tunnel WireGuard manager")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    appearance.cycle()
                } label: {
                    Image(systemName: appearance.current.icon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Appearance: \(appearance.current.label)")

                Button {
                    showingImporter = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    var statusSummary: some View {
        HStack(spacing: 16) {
            StatusPill(
                count: viewModel.tunnels.filter { if case .connected = $0.status { return true } else { return false } }.count,
                label: "Connected",
                color: Theme.success
            )
            StatusPill(
                count: viewModel.tunnels.count,
                label: "Total",
                color: .secondary
            )
            StatusPill(
                count: viewModel.conflicts.count,
                label: "Conflicts",
                color: Theme.error
            )
        }
    }

    var bulkActionBar: some View {
        HStack(spacing: 12) {
            Toggle("Select All", isOn: Binding(
                get: { viewModel.allSelected },
                set: { $0 ? viewModel.selectAll() : viewModel.deselectAll() }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                viewModel.disconnectSelected()
            } label: {
                Label("Disconnect", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.hasSelection)

            Button {
                viewModel.connectSelected()
            } label: {
                Label("Connect", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.hasSelection)
        }
    }

    var tunnelsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.tunnels) { tunnel in
                TunnelCard(
                    tunnel: tunnel,
                    isSelected: viewModel.selectedTunnelIDs.contains(tunnel.id),
                    onToggle: { viewModel.toggle(tunnel) },
                    onBindChange: { viewModel.setBindInterface($0, for: tunnel) },
                    onRemove: { viewModel.remove(tunnel) },
                    onSelectionChange: { viewModel.setSelected(tunnel, isSelected: $0) }
                )
            }
        }
    }

    var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.error)
                Text("Address conflicts detected")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.conflicts) { conflict in
                    Text("• \(conflict.tunnelA) and \(conflict.tunnelB) overlap on \(conflict.overlap).")
                        .font(.callout)
                }
            }

            Text("You can only connect one of these tunnels at a time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.error.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.error.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("No tunnels yet")
                    .font(.title2.weight(.semibold))
                Text("Import a WireGuard config file to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingImporter = true
            } label: {
                Label("Import Config", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }
}

struct StatusPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .shadow(color: .primary.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
