import SwiftUI

/// Popover shown from the (i) button on a tunnel card: configuration details plus live statistics.
struct TunnelInfoView: View {
    let tunnel: Tunnel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                routingSection
                interfaceSection
                if let details = tunnel.details {
                    statisticsSection(details)
                }
                peersSection
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 520)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.Status.icon(for: tunnel.status))
                .font(.title2)
                .foregroundStyle(Theme.Status.color(for: tunnel.status))
            VStack(alignment: .leading, spacing: 3) {
                Text(tunnel.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(status: tunnel.status)
                    if case .connected(let interface) = tunnel.status {
                        Text(interface)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    private var routingSection: some View {
        InfoSection(title: "Routing", icon: "arrow.triangle.branch") {
            let allowed = tunnel.config.allowedIPs
            InfoRow(label: "Allowed IPs") {
                if allowed.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    AddressList(addresses: allowed)
                }
            }
            if tunnel.config.routesAllTraffic {
                Text("All traffic is routed through this tunnel.")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            if let installed = tunnel.details?.installedRoutes, !installed.isEmpty {
                InfoRow(label: "Installed routes") {
                    AddressList(addresses: installed)
                }
            }
        }
    }

    private var interfaceSection: some View {
        InfoSection(title: "Interface", icon: "network") {
            let iface = tunnel.config.interface
            InfoRow(label: "Address") {
                AddressList(addresses: iface.addresses)
            }
            if !iface.dns.isEmpty {
                InfoRow(label: "DNS") {
                    AddressList(addresses: iface.dns)
                }
            }
            if let port = tunnel.details?.listenPort ?? iface.listenPort {
                InfoRow(label: "Listen port", value: "\(port)")
            }
            if let mtu = iface.mtu {
                InfoRow(label: "MTU", value: "\(mtu)")
            }
            if let publicKey = tunnel.details?.publicKey {
                InfoRow(label: "Public key") {
                    KeyText(key: publicKey)
                }
            }
            if let bind = tunnel.bindInterface, !bind.isEmpty {
                InfoRow(label: "Bind to", value: bind)
            }
            InfoRow(label: "Config file", value: tunnel.fileURL.lastPathComponent)
        }
    }

    private func statisticsSection(_ details: TunnelDetails) -> some View {
        InfoSection(title: "Statistics", icon: "chart.bar") {
            HStack(spacing: 12) {
                StatTile(icon: "arrow.down.circle.fill", label: "Received", value: details.formattedRX, rate: details.formattedRXRate, color: Theme.success)
                StatTile(icon: "arrow.up.circle.fill", label: "Sent", value: details.formattedTX, rate: details.formattedTXRate, color: Theme.accent)
            }
            if details.source == .wireguard {
                InfoRow(label: "Last handshake", value: formatRelativeTime(since: details.latestHandshake))
            }
            InfoRow(label: "Updated", value: details.fetchedAt.formatted(date: .omitted, time: .standard))
            if details.source == .system {
                Text("Handshake and per-peer counters need the privileged helper (signed build). Showing interface totals from the system instead.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var peersSection: some View {
        InfoSection(title: tunnel.config.peers.count == 1 ? "Peer" : "Peers (\(tunnel.config.peers.count))", icon: "person.2") {
            ForEach(Array(tunnel.config.peers.enumerated()), id: \.offset) { index, peer in
                let stats = tunnel.details?.peers.first { $0.publicKey == peer.publicKey }
                VStack(alignment: .leading, spacing: 6) {
                    if tunnel.config.peers.count > 1 {
                        Text("Peer \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    InfoRow(label: "Endpoint", value: stats?.endpoint ?? peer.endpoint ?? "—")
                    InfoRow(label: "Public key") {
                        KeyText(key: peer.publicKey)
                    }
                    InfoRow(label: "Allowed IPs") {
                        AddressList(addresses: peer.allowedIPs)
                    }
                    if let keepalive = peer.persistentKeepalive {
                        InfoRow(label: "Keepalive", value: "\(keepalive)s")
                    }
                    if let stats = stats, tunnel.details?.source == .wireguard {
                        InfoRow(label: "Handshake", value: formatRelativeTime(since: stats.latestHandshake))
                        InfoRow(label: "Transfer", value: "↓ \(stats.formattedRX)  ↑ \(stats.formattedTX)")
                    }
                }
                if index < tunnel.config.peers.count - 1 {
                    Divider()
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct InfoRow<Value: View>: View {
    let label: String
    let value: Value

    init(label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            value
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension InfoRow where Value == Text {
    init(label: String, value: String) {
        self.init(label: label) {
            Text(value)
        }
    }
}

private struct AddressList: View {
    let addresses: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if addresses.isEmpty {
                Text("—").foregroundStyle(.secondary)
            }
            ForEach(addresses, id: \.self) { address in
                Text(address)
                    .font(.caption.monospaced())
            }
        }
    }
}

private struct KeyText: View {
    let key: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(key)
            Button {
                copyToClipboard(key)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy public key")
        }
    }
}

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let rate: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(rate ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
