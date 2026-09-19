import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: TunnelListViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MultiGuard")
                        .font(.headline)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            if viewModel.tunnels.isEmpty {
                Text("No tunnels imported")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.tunnels) { tunnel in
                        Button {
                            viewModel.toggle(tunnel)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: Theme.Status.icon(for: tunnel.status))
                                    .foregroundStyle(Theme.Status.color(for: tunnel.status))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tunnel.name)
                                        .lineLimit(1)
                                    Text(tunnel.config.routeSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .help(tunnel.config.allowedIPs.joined(separator: ", "))
                                Spacer()
                                Text(menuStatusText(tunnel.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.0001))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .disabled(tunnel.status == .connecting || tunnel.status == .disconnecting)
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            HStack {
                Button("Open MultiGuard…") {
                    AppDelegate.showMainWindow(openWindow: openWindow)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusLine: String {
        let connected = viewModel.tunnels.filter { if case .connected = $0.status { return true } else { return false } }.count
        if connected == 0 {
            return "No active tunnels"
        } else if connected == 1 {
            return "1 tunnel connected"
        } else {
            return "\(connected) tunnels connected"
        }
    }

    private func menuStatusText(_ status: TunnelStatus) -> String {
        switch status {
        case .disconnected: return "Off"
        case .connecting: return "On…"
        case .connected: return "On"
        case .disconnecting: return "Off…"
        case .failed: return "Error"
        }
    }
}
