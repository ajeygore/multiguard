import SwiftUI

struct TunnelCard: View {
    let tunnel: Tunnel
    let isSelected: Bool
    let onToggle: () -> Void
    let onBindChange: (String?) -> Void
    let onRemove: () -> Void
    let onSelectionChange: (Bool) -> Void
    @State private var bindText: String = ""
    @State private var isHovering = false
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onSelectionChange($0) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 20)
            .help("Select tunnel for bulk actions")

            statusIcon
                .frame(width: 44, height: 44)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(tunnel.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                HStack(spacing: 8) {
                    StatusBadge(status: tunnel.status)
                    Text("• \(tunnel.config.peers.count) peer\(tunnel.config.peers.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                routesLine

                if let details = tunnel.details {
                    HStack(spacing: 12) {
                        DetailItem(icon: "arrow.down.circle", label: "RX", value: details.formattedRX)
                        DetailItem(icon: "arrow.up.circle", label: "TX", value: details.formattedTX)
                        DetailItem(icon: "network", label: "IP", value: details.localIP)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Bind interface", text: $bindText, prompt: Text("en0"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit {
                            onBindChange(bindText.isEmpty ? nil : bindText)
                        }

                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                    .disabled(isBusy)

                    Button {
                        onToggle()
                    } label: {
                        Text(buttonTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonTint)
                    .disabled(isBusy)
                    .overlay(
                        Group {
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(buttonTint.opacity(0.9))
                                    .clipShape(Capsule())
                            }
                        }
                    )
                }

                if case .failed(let message) = tunnel.status {
                    HStack(spacing: 6) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            copyToClipboard(message)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy error to clipboard")
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .primary.opacity(0.05), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            bindText = tunnel.bindInterface ?? ""
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    /// Compact summary of what the tunnel routes (from AllowedIPs), with an (i) button for full details.
    var routesLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Routes: ")
                .font(.caption2)
                .foregroundColor(.secondary)
            + Text(tunnel.config.routeSummary)
                .font(.caption2.weight(.medium))
                .foregroundColor(tunnel.config.routesAllTraffic ? Theme.warning : .primary)

            Button {
                showingInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .help("Details and statistics")
            .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                TunnelInfoView(tunnel: tunnel)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .help(tunnel.config.allowedIPs.joined(separator: ", "))
    }

    var statusIcon: some View {
        Image(systemName: Theme.Status.icon(for: tunnel.status))
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(statusColor)
    }

    var statusColor: Color {
        Theme.Status.color(for: tunnel.status)
    }

    var isBusy: Bool {
        tunnel.status == .connecting || tunnel.status == .disconnecting
    }

    var buttonTitle: String {
        switch tunnel.status {
        case .connected: return "Disconnect"
        case .connecting: return "…"
        case .disconnecting: return "…"
        default: return "Connect"
        }
    }

    var buttonTint: Color {
        switch tunnel.status {
        case .connected: return Theme.error
        default: return Theme.accent
        }
    }
}

struct StatusBadge: View {
    let status: TunnelStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    var text: String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .failed: return "Failed"
        }
    }

    var color: Color {
        Theme.Status.color(for: status)
    }
}

struct DetailItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(label):")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}
