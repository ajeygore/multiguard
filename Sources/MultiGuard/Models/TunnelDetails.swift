import Foundation

struct TunnelDetails: Equatable {
    /// Where the statistics came from. `wireguard` means `wg show <iface> dump` succeeded
    /// (privileged helper or a readable control socket) and per-peer data is live.
    /// `system` means only interface-level counters from `netstat` were available.
    enum Source: Equatable {
        case wireguard
        case system
    }

    struct PeerStats: Equatable, Identifiable {
        var id: String { publicKey }
        let publicKey: String
        let endpoint: String?
        let allowedIPs: [String]
        let latestHandshake: Date?
        let rxBytes: UInt64
        let txBytes: UInt64
        let persistentKeepalive: Int?

        var formattedRX: String { formatBytes(rxBytes) }
        var formattedTX: String { formatBytes(txBytes) }
    }

    let interface: String
    let source: Source
    let fetchedAt: Date
    let txBytes: UInt64
    let rxBytes: UInt64
    /// Bytes per second since the previous sample, if one was available.
    var rxBytesPerSecond: Double?
    var txBytesPerSecond: Double?
    let localIP: String
    let listenPort: Int?
    let publicKey: String?
    /// Routes actually installed in the system routing table for this interface.
    let installedRoutes: [String]
    let peers: [PeerStats]

    var formattedTX: String { formatBytes(txBytes) }
    var formattedRX: String { formatBytes(rxBytes) }

    var formattedRXRate: String? { rxBytesPerSecond.map { formatBytes(UInt64($0)) + "/s" } }
    var formattedTXRate: String? { txBytesPerSecond.map { formatBytes(UInt64($0)) + "/s" } }

    /// Most recent handshake across all peers.
    var latestHandshake: Date? {
        peers.compactMap(\.latestHandshake).max()
    }

    /// Derive throughput from a previous sample of the same interface.
    func withRates(since previous: TunnelDetails?) -> TunnelDetails {
        guard let previous = previous, previous.interface == interface else { return self }
        let elapsed = fetchedAt.timeIntervalSince(previous.fetchedAt)
        guard elapsed > 0 else { return self }
        var copy = self
        copy.rxBytesPerSecond = rxBytes >= previous.rxBytes ? Double(rxBytes - previous.rxBytes) / elapsed : 0
        copy.txBytesPerSecond = txBytes >= previous.txBytes ? Double(txBytes - previous.txBytes) / elapsed : 0
        return copy
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var index = 0
    while value >= 1024 && index < units.count - 1 {
        value /= 1024
        index += 1
    }
    return String(format: "%.2f %@", value, units[index])
}

func formatRelativeTime(since date: Date?, now: Date = Date()) -> String {
    guard let date = date else { return "Never" }
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 5 { return "Just now" }
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m \(seconds % 60)s ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m ago" }
    let days = hours / 24
    return "\(days)d \(hours % 24)h ago"
}
